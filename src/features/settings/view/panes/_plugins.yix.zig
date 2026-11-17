// GENERATED FILE, do not edit: generated from plugins.yix; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! 协议插件（第 5 类）面板正文（F-set-plugins，人工验收反馈第 10 条）：两级导航。
//!
//! - 列表页（Pencil `T5k96`，`Location{ .page = 5 }`）：按来源分组的面板（已内置 / 随应用提供），每个插件一行
//!   （`R.DrillRow`：图标、名称、清单说明、版本、箭头），点一行进入该插件的详情页；最后是“计划中”面板，只列路线条目
//!   （`host/plugin_roadmap.zig`：名称 + “{目标版本} 版本待实施”，不可点击，没有能力数、版本与箭头）。
//! - 详情页（`KUKQ5`，`Location{ .page = 5, .sub = <注册表下标> }`）：头部卡片（图标、名称、说明、来源标签 `W.Tag`）与
//!   管理说明；“插件信息”（版本、权限：值 + 原生“?”提示全文）；插件自带的偏好字段（原生开关 / 输入框 / 选择框，
//!   生效时机是原生“?”式提示按钮）。页头后退 / 前进、搜索、滚动位置走设置窗口的两级导航机制。
//!
//! - 状态（Q5，Pencil XqqLV 稿 2）：只有随应用提供的插件有。开关是原生 `W.Switch`，待重启 / 已禁用提示是原生 `W.Alert`
//!   （“立即重启”是 Alert 的原生动作行），状态标签是原生 `W.Tag`。
//!
//! 插件是运行时数据：行、文案、test_id 都由 view-model 从注册表派生（`m.plugin_pane`、`vm.plugin*`），本文件只摆结构。
//! 只展示注册的元数据，不为插件编造能力；“计划中”只来自有设计文档的路线条目。
const std = @import("std");
const ui = @import("ui");
const W = ui.widgets;
const m = @import("../../model/view_model.zig");
const R = @import("../components/_rows.yix.zig");
const S = @import("../_styles.yss.zig");
const P = @import("_plugins.yss.zig");
const D = m.plugin_pane;

fn send(vm: *m.ViewModel, intent: m.Intent) void {
    vm.dispatch(intent);
}
fn popup(vm: *m.ViewModel, id: []const u8) bool {
    return vm.popupOpen(id);
}
fn setPopup(vm: *m.ViewModel, id: []const u8, open: bool) void {
    vm.dispatch(m.Intent.popupChanged(id, open));
}

// ── 列表页 ──

fn groupId(group: m.PluginGroup) []const u8 {
    return D.groupId(group);
}
fn groupHeaderId(group: m.PluginGroup) []const u8 {
    return D.groupHeaderId(group);
}
fn groupMetaId(group: m.PluginGroup) []const u8 {
    return D.groupMetaId(group);
}
fn groupTitle(group: m.PluginGroup) []const u8 {
    return D.groupTitle(group);
}
fn groupShown(vm: *m.ViewModel, group: m.PluginGroup) bool {
    return vm.pluginGroupShown(group);
}
fn items(vm: *m.ViewModel, group: m.PluginGroup) []const m.DrillItem {
    return vm.pluginItems(group);
}
fn listEmpty(vm: *m.ViewModel) bool {
    return vm.pluginListEmpty();
}

/// 一个来源分组（`RvB77` / `hhc8s`）：Pane Header（标题 + “3 个协议 · 随应用管理”）+ 行卡片。
fn Group(args: anytype) ui.view.ComponentOf(__yix_Group) {
    return ui.view.component(__yix_Group, ui.reactive.props.coerce(GroupProps, args));
}
const GroupProps = struct {
    vm: ui.Source(*m.ViewModel),
    group: ui.Source(m.PluginGroup),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = Group;
    pub const __yix_preview_mount = __yix_Group;
};
fn __yix_Group(__yix_props: GroupProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    const group = __yix_props.group;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, .group = group, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Group", .receiver = "box", .tokens = "box testId = groupId ( group ) ; style = @static; visible = groupShown ( vm , group ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "groupId ( group ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . pane ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "groupShown ( vm , group ) ", .kind = .property, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .group = __yix_view_ctx.group, .vm = __yix_view_ctx.vm, }, ui.view.box(.{ .test_id = __yix_d1: {
        const __yix_T = @TypeOf(groupId(__yix_view_ctx.group.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .group = __yix_view_ctx.group, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return groupId(__yix_ctx.group.get());
        } }.__yix_compute);
    }, .style = S.pane, .visible = __yix_d2: {
        const __yix_T = @TypeOf(groupShown(__yix_view_ctx.vm.peek(), __yix_view_ctx.group.peek()));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .group = __yix_view_ctx.group, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return groupShown(__yix_ctx.vm.get(), __yix_ctx.group.get());
        } }.__yix_compute);
    }, }, .{
            ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Group", .receiver = "box", .tokens = "box testId = groupHeaderId ( group ) ; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "groupHeaderId ( group ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . pane_header ", .kind = .style, .literal = null }, } }, .{ .group = __yix_view_ctx.group, .vm = __yix_view_ctx.vm, }, ui.view.box(.{ .test_id = __yix_d3: {
        const __yix_T = @TypeOf(groupHeaderId(__yix_view_ctx.group.peek()));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .group = __yix_view_ctx.group, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return groupHeaderId(__yix_ctx.group.get());
        } }.__yix_compute);
    }, .style = S.pane_header, }, .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Group", .receiver = "text", .tokens = "text style = @static; groupTitle ( group )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . pane_title ", .kind = .style, .literal = null }, } }, .{ .group = __yix_view_ctx.group, }, ui.view.text(.{ .style = S.pane_title, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d4: {
        const __yix_T = @TypeOf(groupTitle(__yix_view_ctx.group.peek()));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .group = __yix_view_ctx.group, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return groupTitle(__yix_ctx.group.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d4: {
        const __yix_T = @TypeOf(groupTitle(__yix_view_ctx.group.peek()));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .group = __yix_view_ctx.group, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return groupTitle(__yix_ctx.group.get());
        } }.__yix_compute);
    }, }))),
                ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Group", .receiver = "spacer", .tokens = "spacer ", .literal_text = null, .attributes = &.{ } }, .{ }, ui.view.spacer()),
                ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Group", .receiver = "text", .tokens = "text testId = groupMetaId ( group ) ; style = @static; box = S . pane_meta_box ; vm . pluginGroupMeta ( group )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "groupMetaId ( group ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . pane_meta ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . pane_meta_box ", .kind = .property, .literal = null }, } }, .{ .group = __yix_view_ctx.group, .vm = __yix_view_ctx.vm, }, ui.view.text(.{ .test_id = __yix_d5: {
        const __yix_T = @TypeOf(groupMetaId(__yix_view_ctx.group.peek()));
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ .group = __yix_view_ctx.group, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return groupMetaId(__yix_ctx.group.get());
        } }.__yix_compute);
    }, .style = S.pane_meta, .box = S.pane_meta_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d6: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().pluginGroupMeta(__yix_view_ctx.group.peek()));
        break :__yix_d6 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .group = __yix_view_ctx.group, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().pluginGroupMeta(__yix_ctx.group.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d6: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().pluginGroupMeta(__yix_view_ctx.group.peek()));
        break :__yix_d6 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .group = __yix_view_ctx.group, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().pluginGroupMeta(__yix_ctx.group.get());
        } }.__yix_compute);
    }, }))),
            })),
            ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Group", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . pane_body ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .group = __yix_view_ctx.group, }, ui.view.box(.{ .style = S.pane_body, }, .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Group", .receiver = "control", .tokens = "for ( items ( vm , group ) ) | item | < R . DrillRow key = { item . key } vm = { vm } item = { item } / > " }, .{ .vm = __yix_view_ctx.vm, .group = __yix_view_ctx.group, }, __yix_e1: { const __yix_items_1 = __yix_d1: {
        const __yix_T = @TypeOf(items(__yix_view_ctx.vm.peek(), __yix_view_ctx.group.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .group = __yix_view_ctx.group, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return items(__yix_ctx.vm.get(), __yix_ctx.group.get());
        } }.__yix_compute);
    }; break :__yix_e1 ui.view.eachWith(.{ .vm = __yix_view_ctx.vm, }, __yix_items_1, struct { fn __yix_k(item: ui.view.yixItem(@TypeOf(__yix_items_1))) u64 { return ui.view.keyOf(item.key); } }.__yix_k, struct { fn __yix_row(__yix_row_1: anytype, item: ui.Source(ui.view.yixItem(@TypeOf(__yix_items_1))), __yix_scope_1: *ui.Scope, __yix_cx_1: *ui.Cx) anyerror!*ui.Node { return ui.view.render(__yix_scope_1, __yix_cx_1, ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Group/keyword_for:1", .receiver = "R.DrillRow", .tokens = "< R . DrillRow key = { item . key } vm = { vm } item = { item } / > ", .literal_text = null, .attributes = &.{ .{ .name = "key", .tokens = "item . key ", .kind = .property, .literal = null }, .{ .name = "vm", .tokens = "vm ", .kind = .property, .literal = null }, .{ .name = "item", .tokens = "item ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_row_1.vm, .item = item, }, __yix_builder_30: { try ui.view.previewCheckBuilder(__yix_scope_1, R.DrillRow); break :__yix_builder_30 R.DrillRow(.{ .vm = __yix_row_1.vm, .item = item, }); })); } }.__yix_row); }),
            })),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "Group";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

fn plannedShown(vm: *m.ViewModel) bool {
    return vm.pluginPlannedShown();
}
fn plannedItems(vm: *m.ViewModel) []const m.PlannedItem {
    return vm.pluginPlannedItems();
}
fn plannedIcon(item: m.PlannedItem) ui.SvgAsset {
    return ui.icons.get(item.icon) orelse ui.icons.plug;
}

/// 计划行（`Wlmxe`）：图标底 + 名称 / “0.5 版本待实施”，行间发丝线同 `DrillRow`；不可点击。
fn PlannedRow(args: anytype) ui.view.ComponentOf(__yix_PlannedRow) {
    return ui.view.component(__yix_PlannedRow, ui.reactive.props.coerce(PlannedRowProps, args));
}
const PlannedRowProps = struct {
    item: ui.Source(m.PlannedItem),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = PlannedRow;
    pub const __yix_preview_mount = __yix_PlannedRow;
};
fn __yix_PlannedRow(__yix_props: PlannedRowProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const item = __yix_props.item;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .item = item, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "PlannedRow", .receiver = "box", .tokens = "box testId = item . row_id ; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "item . row_id ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "P . planned_row ", .kind = .style, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .item = __yix_view_ctx.item, }, ui.view.box(.{ .test_id = __yix_d1: {
        const __yix_T = @TypeOf(__yix_view_ctx.item.peek().row_id);
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .item = __yix_view_ctx.item, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.item.get().row_id;
        } }.__yix_compute);
    }, .style = P.planned_row, }, .{
            ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "PlannedRow", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . overview_tile ", .kind = .style, .literal = null }, } }, .{ .item = __yix_view_ctx.item, }, ui.view.box(.{ .style = S.overview_tile, }, .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "PlannedRow", .receiver = "icon", .tokens = "icon src = plannedIcon ( item ) ; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "src", .tokens = "plannedIcon ( item ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "P . planned_icon ", .kind = .style, .literal = null }, } }, .{ .item = __yix_view_ctx.item, }, ui.view.icon(.{ .style = P.planned_icon, }, __yix_d2: {
        const __yix_T = @TypeOf(plannedIcon(__yix_view_ctx.item.peek()));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .item = __yix_view_ctx.item, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return plannedIcon(__yix_ctx.item.get());
        } }.__yix_compute);
    })),
            })),
            ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "PlannedRow", .receiver = "box", .tokens = "box style = S . DrillInner . of ( . { . last = item . last } ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . DrillInner . of ( . { . last = item . last } ) ", .kind = .style, .literal = null }, } }, .{ .item = __yix_view_ctx.item, }, ui.view.box(.{ .style = S.DrillInner.of(.{ .last = __yix_d3: {
        const __yix_T = @TypeOf(__yix_view_ctx.item.peek().last);
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .item = __yix_view_ctx.item, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.item.get().last;
        } }.__yix_compute);
    } }), }, .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "PlannedRow", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . drill_copy ", .kind = .style, .literal = null }, } }, .{ .item = __yix_view_ctx.item, }, ui.view.box(.{ .style = S.drill_copy, }, .{
                    ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "PlannedRow", .receiver = "text", .tokens = "text testId = item . title_id ; style = @static; box = S . drill_text_box ; item . title  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "item . title_id ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "P . planned_title ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . drill_text_box ", .kind = .property, .literal = null }, } }, .{ .item = __yix_view_ctx.item, }, ui.view.text(.{ .test_id = __yix_d4: {
        const __yix_T = @TypeOf(__yix_view_ctx.item.peek().title_id);
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .item = __yix_view_ctx.item, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.item.get().title_id;
        } }.__yix_compute);
    }, .style = P.planned_title, .box = S.drill_text_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d5: {
        const __yix_T = @TypeOf(__yix_view_ctx.item.peek().title);
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ .item = __yix_view_ctx.item, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.item.get().title;
        } }.__yix_compute);
    }), ""), .{ __yix_d5: {
        const __yix_T = @TypeOf(__yix_view_ctx.item.peek().title);
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ .item = __yix_view_ctx.item, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.item.get().title;
        } }.__yix_compute);
    }, }))),
                    ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "PlannedRow", .receiver = "text", .tokens = "text testId = item . summary_id ; style = @static; box = S . drill_text_box ; item . summary  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "item . summary_id ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . drill_summary ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . drill_text_box ", .kind = .property, .literal = null }, } }, .{ .item = __yix_view_ctx.item, }, ui.view.text(.{ .test_id = __yix_d6: {
        const __yix_T = @TypeOf(__yix_view_ctx.item.peek().summary_id);
        break :__yix_d6 try __yix_view_scope.derive(__yix_T, .{ .item = __yix_view_ctx.item, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.item.get().summary_id;
        } }.__yix_compute);
    }, .style = S.drill_summary, .box = S.drill_text_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d7: {
        const __yix_T = @TypeOf(__yix_view_ctx.item.peek().summary);
        break :__yix_d7 try __yix_view_scope.derive(__yix_T, .{ .item = __yix_view_ctx.item, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.item.get().summary;
        } }.__yix_compute);
    }), ""), .{ __yix_d7: {
        const __yix_T = @TypeOf(__yix_view_ctx.item.peek().summary);
        break :__yix_d7 try __yix_view_scope.derive(__yix_T, .{ .item = __yix_view_ctx.item, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.item.get().summary;
        } }.__yix_compute);
    }, }))),
                })),
            })),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "PlannedRow";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

/// “计划中”（`g3bxO3`）：页头只有标题，没有计数。
fn Planned(args: anytype) ui.view.ComponentOf(__yix_Planned) {
    return ui.view.component(__yix_Planned, ui.reactive.props.coerce(PlannedProps, args));
}
const PlannedProps = struct {
    vm: ui.Source(*m.ViewModel),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = Planned;
    pub const __yix_preview_mount = __yix_Planned;
};
fn __yix_Planned(__yix_props: PlannedProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Planned", .receiver = "box", .tokens = "box testId = @static; style = @static; visible = plannedShown ( vm ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"settings.plugins.planned\" ", .kind = .property, .literal = .{ .text = "settings.plugins.planned" } }, .{ .name = "style", .tokens = "S . pane ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "plannedShown ( vm ) ", .kind = .property, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .vm = __yix_view_ctx.vm, }, ui.view.box(.{ .test_id = "settings.plugins.planned", .style = S.pane, .visible = __yix_d1: {
        const __yix_T = @TypeOf(plannedShown(__yix_view_ctx.vm.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return plannedShown(__yix_ctx.vm.get());
        } }.__yix_compute);
    }, }, .{
            ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Planned", .receiver = "box", .tokens = "box testId = @static; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"settings.plugins.planned.header\" ", .kind = .property, .literal = .{ .text = "settings.plugins.planned.header" } }, .{ .name = "style", .tokens = "S . pane_header ", .kind = .style, .literal = null }, } }, .{ }, ui.view.box(.{ .test_id = "settings.plugins.planned.header", .style = S.pane_header, }, .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Planned", .receiver = "text", .tokens = "text style = @static; D . planned_title  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . pane_title ", .kind = .style, .literal = null }, } }, .{ }, ui.view.text(.{ .style = S.pane_title, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(D.planned_title), ""), .{ D.planned_title, }))),
            })),
            ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Planned", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . pane_body ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.box(.{ .style = S.pane_body, }, .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Planned", .receiver = "control", .tokens = "for ( plannedItems ( vm ) ) | item | < PlannedRow key = { item . key } item = { item } / > " }, .{ .vm = __yix_view_ctx.vm, }, __yix_e1: { const __yix_items_1 = __yix_d1: {
        const __yix_T = @TypeOf(plannedItems(__yix_view_ctx.vm.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return plannedItems(__yix_ctx.vm.get());
        } }.__yix_compute);
    }; break :__yix_e1 ui.view.eachWith(.{ }, __yix_items_1, struct { fn __yix_k(item: ui.view.yixItem(@TypeOf(__yix_items_1))) u64 { return ui.view.keyOf(item.key); } }.__yix_k, struct { fn __yix_row(__yix_row_1: anytype, item: ui.Source(ui.view.yixItem(@TypeOf(__yix_items_1))), __yix_scope_1: *ui.Scope, __yix_cx_1: *ui.Cx) anyerror!*ui.Node { _ = __yix_row_1; return ui.view.render(__yix_scope_1, __yix_cx_1, ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Planned/keyword_for:1", .receiver = "PlannedRow", .tokens = "< PlannedRow key = { item . key } item = { item } / > ", .literal_text = null, .attributes = &.{ .{ .name = "key", .tokens = "item . key ", .kind = .property, .literal = null }, .{ .name = "item", .tokens = "item ", .kind = .property, .literal = null }, } }, .{ .item = item, }, __yix_builder_30: { try ui.view.previewCheckBuilder(__yix_scope_1, PlannedRow); break :__yix_builder_30 PlannedRow(.{ .item = item, }); })); } }.__yix_row); }),
            })),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "Planned";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

fn List(args: anytype) ui.view.ComponentOf(__yix_List) {
    return ui.view.component(__yix_List, ui.reactive.props.coerce(ListProps, args));
}
const ListProps = struct {
    vm: ui.Source(*m.ViewModel),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = List;
    pub const __yix_preview_mount = __yix_List;
};
fn __yix_List(__yix_props: ListProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "List", .receiver = "box", .tokens = "box testId = @static; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"settings.plugins.groups\" ", .kind = .property, .literal = .{ .text = "settings.plugins.groups" } }, .{ .name = "style", .tokens = "P . panes ", .kind = .style, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .vm = __yix_view_ctx.vm, }, ui.view.box(.{ .test_id = "settings.plugins.groups", .style = P.panes, }, .{
            ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "List", .receiver = "Group", .tokens = "< Group vm = { vm } group = { . builtin } / > ", .literal_text = null, .attributes = &.{ .{ .name = "vm", .tokens = "vm ", .kind = .property, .literal = null }, .{ .name = "group", .tokens = ". builtin ", .kind = .property, .literal = .{ .enum_name = "builtin" } }, } }, .{ .vm = __yix_view_ctx.vm, }, __yix_builder_5259: { try ui.view.previewCheckBuilder(__yix_view_scope, Group); break :__yix_builder_5259 Group(.{ .vm = __yix_view_ctx.vm, .group = .builtin, }); }),
            ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "List", .receiver = "Group", .tokens = "< Group vm = { vm } group = { . bundled } / > ", .literal_text = null, .attributes = &.{ .{ .name = "vm", .tokens = "vm ", .kind = .property, .literal = null }, .{ .name = "group", .tokens = ". bundled ", .kind = .property, .literal = .{ .enum_name = "bundled" } }, } }, .{ .vm = __yix_view_ctx.vm, }, __yix_builder_5306: { try ui.view.previewCheckBuilder(__yix_view_scope, Group); break :__yix_builder_5306 Group(.{ .vm = __yix_view_ctx.vm, .group = .bundled, }); }),
            ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "List", .receiver = "box", .tokens = "box testId = @static; visible = listEmpty ( vm ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"settings.plugins.empty\" ", .kind = .property, .literal = .{ .text = "settings.plugins.empty" } }, .{ .name = "visible", .tokens = "listEmpty ( vm ) ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.box(.{ .test_id = "settings.plugins.empty", .visible = __yix_d1: {
        const __yix_T = @TypeOf(listEmpty(__yix_view_ctx.vm.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return listEmpty(__yix_ctx.vm.get());
        } }.__yix_compute);
    }, }, .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "List", .receiver = "W.Empty", .tokens = "< W . Empty icon = { ui . icons . get ( \"puzzle\" ) . ? } title = \"没有已注册的插件\" description = \"已内置与随应用提供的插件会列在这里。\" / > ", .literal_text = null, .attributes = &.{ .{ .name = "icon", .tokens = "ui . icons . get ( \"puzzle\" ) . ? ", .kind = .property, .literal = null }, .{ .name = "title", .tokens = "\"没有已注册的插件\" ", .kind = .property, .literal = .{ .text = "没有已注册的插件" } }, .{ .name = "description", .tokens = "\"已内置与随应用提供的插件会列在这里。\" ", .kind = .property, .literal = .{ .text = "已内置与随应用提供的插件会列在这里。" } }, } }, .{ }, __yix_builder_5431: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Empty); break :__yix_builder_5431 W.Empty(.{ .icon = __yix_call3: {
        const __yix_Raw = @TypeOf(ui.icons.get("puzzle").?);
        break :__yix_call3 if (comptime !ui.view.yixCallMayDerive(__yix_Raw)) ui.icons.get("puzzle").? else __yix_d2: {
        const __yix_T = if (ui.view.attrType(W.Empty, "icon")) |__yix_A| __yix_A else @TypeOf(ui.icons.get("puzzle").?);
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            _ = __yix_ctx;
            return ui.icons.get("puzzle").?;
        } }.__yix_compute);
    };
    }, .title = "没有已注册的插件", .description = "已内置与随应用提供的插件会列在这里。", }); }),
            })),
            ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "List", .receiver = "Planned", .tokens = "< Planned vm = { vm } / > ", .literal_text = null, .attributes = &.{ .{ .name = "vm", .tokens = "vm ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, __yix_builder_5608: { try ui.view.previewCheckBuilder(__yix_view_scope, Planned); break :__yix_builder_5608 Planned(.{ .vm = __yix_view_ctx.vm, }); }),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "List";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

// ── 详情页 ──

fn detailIndex(vm: *m.ViewModel) u8 {
    return vm.pluginDetail() orelse 0;
}
fn detailShown(vm: *m.ViewModel) bool {
    return vm.pluginDetailShown();
}
fn pid(vm: *m.ViewModel, index: u8, part: m.PluginPart) []const u8 {
    return vm.pluginId(index, part);
}
fn icon(vm: *m.ViewModel, index: u8) ui.SvgAsset {
    return ui.icons.get(vm.pluginIcon(index)) orelse ui.icons.plug;
}

/// 概要（`B57vb`）：头部卡片 + 管理说明。
fn Summary(args: anytype) ui.view.ComponentOf(__yix_Summary) {
    return ui.view.component(__yix_Summary, ui.reactive.props.coerce(SummaryProps, args));
}
const SummaryProps = struct {
    vm: ui.Source(*m.ViewModel),
    index: ui.Source(u8),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = Summary;
    pub const __yix_preview_mount = __yix_Summary;
};
fn __yix_Summary(__yix_props: SummaryProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    const index = __yix_props.index;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, .index = index, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Summary", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "P . summary_pane ", .kind = .style, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, ui.view.box(.{ .style = P.summary_pane, }, .{
            ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Summary", .receiver = "box", .tokens = "box testId = pid ( vm , index , . header ) ; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "pid ( vm , index , . header ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "P . head_card ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, ui.view.box(.{ .test_id = __yix_d1: {
        const __yix_T = @TypeOf(pid(__yix_view_ctx.vm.peek(), __yix_view_ctx.index.peek(), .header));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return pid(__yix_ctx.vm.get(), __yix_ctx.index.get(), .header);
        } }.__yix_compute);
    }, .style = P.head_card, }, .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Summary", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "P . head_tile ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, ui.view.box(.{ .style = P.head_tile, }, .{
                    ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Summary", .receiver = "icon", .tokens = "icon src = icon ( vm , index ) ; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "src", .tokens = "icon ( vm , index ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "P . head_icon ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, ui.view.icon(.{ .style = P.head_icon, }, __yix_d2: {
        const __yix_T = @TypeOf(icon(__yix_view_ctx.vm.peek(), __yix_view_ctx.index.peek()));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return icon(__yix_ctx.vm.get(), __yix_ctx.index.get());
        } }.__yix_compute);
    })),
                })),
                ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Summary", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "P . head_copy ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, ui.view.box(.{ .style = P.head_copy, }, .{
                    ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Summary", .receiver = "text", .tokens = "text style = @static; box = P . head_text_box ; vm . pluginName ( index )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "P . head_name ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "P . head_text_box ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, ui.view.text(.{ .style = P.head_name, .box = P.head_text_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d3: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().pluginName(__yix_view_ctx.index.peek()));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().pluginName(__yix_ctx.index.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d3: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().pluginName(__yix_view_ctx.index.peek()));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().pluginName(__yix_ctx.index.get());
        } }.__yix_compute);
    }, }))),
                    ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Summary", .receiver = "text", .tokens = "text testId = pid ( vm , index , . summary ) ; style = @static; box = P . head_text_box ; vm . pluginDescription ( index )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "pid ( vm , index , . summary ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "P . head_summary ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "P . head_text_box ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, ui.view.text(.{ .test_id = __yix_d4: {
        const __yix_T = @TypeOf(pid(__yix_view_ctx.vm.peek(), __yix_view_ctx.index.peek(), .summary));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return pid(__yix_ctx.vm.get(), __yix_ctx.index.get(), .summary);
        } }.__yix_compute);
    }, .style = P.head_summary, .box = P.head_text_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d5: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().pluginDescription(__yix_view_ctx.index.peek()));
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().pluginDescription(__yix_ctx.index.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d5: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().pluginDescription(__yix_view_ctx.index.peek()));
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().pluginDescription(__yix_ctx.index.get());
        } }.__yix_compute);
    }, }))),
                })),
                ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Summary", .receiver = "control", .tokens = "if ( vm . pluginStateTagShown ( index ) ) < W . Tag testId = { pid ( vm , index , . state ) } label = { vm . pluginStateTag ( index ) } color = { stateColor ( vm , index ) } size = { . sm } / > " }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, ui.view.lazyIf(__yix_d4: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().pluginStateTagShown(__yix_view_ctx.index.peek()));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().pluginStateTagShown(__yix_ctx.index.get());
        } }.__yix_compute);
    }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_b(__yix_b1_0: anytype, __yix_bs1_0: *ui.Scope, __yix_bc1_0: *ui.Cx, __yix_bk1_0: ui.view.Sink) anyerror!void { return ui.view.emit(__yix_bs1_0, __yix_bc1_0, __yix_bk1_0, .{ ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Summary/keyword_if:1/branch:0", .receiver = "W.Tag", .tokens = "< W . Tag testId = { pid ( vm , index , . state ) } label = { vm . pluginStateTag ( index ) } color = { stateColor ( vm , index ) } size = { . sm } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "pid ( vm , index , . state ) ", .kind = .property, .literal = null }, .{ .name = "label", .tokens = "vm . pluginStateTag ( index ) ", .kind = .property, .literal = null }, .{ .name = "color", .tokens = "stateColor ( vm , index ) ", .kind = .property, .literal = null }, .{ .name = "size", .tokens = ". sm ", .kind = .property, .literal = .{ .enum_name = "sm" } }, } }, .{ .vm = __yix_b1_0.vm, .index = __yix_b1_0.index, }, ui.view.templateAttrs(.{ .test_id = __yix_d1: {
        const __yix_T = if (ui.view.attrType(W.Tag, "test_id")) |__yix_A| __yix_A else @TypeOf(pid(__yix_b1_0.vm.peek(), __yix_b1_0.index.peek(), .state));
        break :__yix_d1 try __yix_bs1_0.derive(__yix_T, .{ .vm = __yix_b1_0.vm, .index = __yix_b1_0.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return pid(__yix_ctx.vm.get(), __yix_ctx.index.get(), .state);
        } }.__yix_compute);
    }, }, __yix_builder_35: { try ui.view.previewCheckBuilder(__yix_bs1_0, W.Tag); break :__yix_builder_35 W.Tag(.{ .label = __yix_d2: {
        const __yix_T = if (ui.view.attrType(W.Tag, "label")) |__yix_A| __yix_A else @TypeOf(__yix_b1_0.vm.peek().pluginStateTag(__yix_b1_0.index.peek()));
        break :__yix_d2 try __yix_bs1_0.derive(__yix_T, .{ .vm = __yix_b1_0.vm, .index = __yix_b1_0.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().pluginStateTag(__yix_ctx.index.get());
        } }.__yix_compute);
    }, .color = __yix_d3: {
        const __yix_T = if (ui.view.attrType(W.Tag, "color")) |__yix_A| __yix_A else @TypeOf(stateColor(__yix_b1_0.vm.peek(), __yix_b1_0.index.peek()));
        break :__yix_d3 try __yix_bs1_0.derive(__yix_T, .{ .vm = __yix_b1_0.vm, .index = __yix_b1_0.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return stateColor(__yix_ctx.vm.get(), __yix_ctx.index.get());
        } }.__yix_compute);
    }, .size = .sm, }); })) }); } }.__yix_b, null)),
                ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Summary", .receiver = "W.Tag", .tokens = "< W . Tag testId = { pid ( vm , index , . origin ) } label = { vm . pluginOriginTag ( index ) } size = { . sm } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "pid ( vm , index , . origin ) ", .kind = .property, .literal = null }, .{ .name = "label", .tokens = "vm . pluginOriginTag ( index ) ", .kind = .property, .literal = null }, .{ .name = "size", .tokens = ". sm ", .kind = .property, .literal = .{ .enum_name = "sm" } }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, ui.view.templateAttrs(.{ .test_id = __yix_d6: {
        const __yix_T = if (ui.view.attrType(W.Tag, "test_id")) |__yix_A| __yix_A else @TypeOf(pid(__yix_view_ctx.vm.peek(), __yix_view_ctx.index.peek(), .origin));
        break :__yix_d6 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return pid(__yix_ctx.vm.get(), __yix_ctx.index.get(), .origin);
        } }.__yix_compute);
    }, }, __yix_builder_6918: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Tag); break :__yix_builder_6918 W.Tag(.{ .label = __yix_d7: {
        const __yix_T = if (ui.view.attrType(W.Tag, "label")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().pluginOriginTag(__yix_view_ctx.index.peek()));
        break :__yix_d7 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().pluginOriginTag(__yix_ctx.index.get());
        } }.__yix_compute);
    }, .size = .sm, }); })),
            })),
            ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Summary", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "P . note_wrap ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, ui.view.box(.{ .style = P.note_wrap, }, .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Summary", .receiver = "text", .tokens = "text testId = pid ( vm , index , . version_message ) ; style = @static; box = P . note_box ; vm . pluginNote ( index )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "pid ( vm , index , . version_message ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "P . note ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "P . note_box ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, ui.view.text(.{ .test_id = __yix_d8: {
        const __yix_T = @TypeOf(pid(__yix_view_ctx.vm.peek(), __yix_view_ctx.index.peek(), .version_message));
        break :__yix_d8 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return pid(__yix_ctx.vm.get(), __yix_ctx.index.get(), .version_message);
        } }.__yix_compute);
    }, .style = P.note, .box = P.note_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d9: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().pluginNote(__yix_view_ctx.index.peek()));
        break :__yix_d9 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().pluginNote(__yix_ctx.index.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d9: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().pluginNote(__yix_view_ctx.index.peek()));
        break :__yix_d9 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().pluginNote(__yix_ctx.index.get());
        } }.__yix_compute);
    }, }))),
            })),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "Summary";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

// ── 状态（随应用插件的启用开关，PLUGIN_ARCH_PLAN 6.2.1 Q5；Pencil XqqLV 稿 2） ──

fn stateColor(vm: *m.ViewModel, index: u8) W.TagColor {
    return if (vm.pluginPending(index)) .warning else .neutral;
}
fn toggleShown(vm: *m.ViewModel, index: u8) bool {
    return vm.pluginToggleShown(index);
}
fn setEnabled(vm: *m.ViewModel, index: u8, value: bool) void {
    vm.dispatch(m.Intent.setPluginEnabled(index, value));
}
fn restart(vm: *m.ViewModel) void {
    vm.dispatch(m.Intent.runCommand(.restart_app));
}
fn enabledA11y(vm: *m.ViewModel, index: u8) ?ui.A11yProps {
    return .{ .role = .switch_role, .label = vm.pluginToggleLabel(index), .checked = vm.pluginEnabledDraft(index), .disabled = vm.isSaving() };
}

/// “状态”分组（41 号说明稿）：Pane Header“状态”+ 右侧“重启后生效”，一行 Setting（标签 + 说明 + 原生 `W.Switch`）。
/// 只有随应用提供的插件有这一组（Q5a）。拨动开关是“改了未保存”（SH1gb，沿用保存栏）；保存后与本次启动的状态不同时显示
/// 原生 warning `W.Alert` 与“立即重启”（NHr2L / DzPbO）；本次没有加载时显示原生 info `W.Alert`（B0QXg6 / IeCzY）。
fn Status(args: anytype) ui.view.ComponentOf(__yix_Status) {
    return ui.view.component(__yix_Status, ui.reactive.props.coerce(StatusProps, args));
}
const StatusProps = struct {
    vm: ui.Source(*m.ViewModel),
    index: ui.Source(u8),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = Status;
    pub const __yix_preview_mount = __yix_Status;
};
fn __yix_Status(__yix_props: StatusProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    const index = __yix_props.index;
    try ui.view.previewCheckSetup(scope, false);
    const a11y = __yix_d1: {
        const __yix_T = @TypeOf(enabledA11y(vm.peek(), index.peek()));
        break :__yix_d1 try scope.derive(__yix_T, .{ .vm = vm, .index = index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return enabledA11y(__yix_ctx.vm.get(), __yix_ctx.index.get());
        } }.__yix_compute);
    };
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, .index = index, .a11y = a11y, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Status", .receiver = "box", .tokens = "box testId = pid ( vm , index , . status ) ; style = @static; visible = toggleShown ( vm , index ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "pid ( vm , index , . status ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . pane ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "toggleShown ( vm , index ) ", .kind = .property, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, .a11y = __yix_view_ctx.a11y, }, ui.view.box(.{ .test_id = __yix_d2: {
        const __yix_T = @TypeOf(pid(__yix_view_ctx.vm.peek(), __yix_view_ctx.index.peek(), .status));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return pid(__yix_ctx.vm.get(), __yix_ctx.index.get(), .status);
        } }.__yix_compute);
    }, .style = S.pane, .visible = __yix_d3: {
        const __yix_T = @TypeOf(toggleShown(__yix_view_ctx.vm.peek(), __yix_view_ctx.index.peek()));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return toggleShown(__yix_ctx.vm.get(), __yix_ctx.index.get());
        } }.__yix_compute);
    }, }, .{
            ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Status", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . pane_header ", .kind = .style, .literal = null }, } }, .{ }, ui.view.box(.{ .style = S.pane_header, }, .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Status", .receiver = "text", .tokens = "text style = @static; D . status_title  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . pane_title ", .kind = .style, .literal = null }, } }, .{ }, ui.view.text(.{ .style = S.pane_title, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(D.status_title), ""), .{ D.status_title, }))),
                ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Status", .receiver = "spacer", .tokens = "spacer ", .literal_text = null, .attributes = &.{ } }, .{ }, ui.view.spacer()),
                ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Status", .receiver = "text", .tokens = "text style = @static; box = S . pane_meta_box ; D . status_meta  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . pane_meta ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . pane_meta_box ", .kind = .property, .literal = null }, } }, .{ }, ui.view.text(.{ .style = S.pane_meta, .box = S.pane_meta_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(D.status_meta), ""), .{ D.status_meta, }))),
            })),
            ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Status", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . pane_body ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, .a11y = __yix_view_ctx.a11y, }, ui.view.box(.{ .style = S.pane_body, }, .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Status", .receiver = "box", .tokens = "box style = S . SettingRow . of ( . { . last = true } ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . SettingRow . of ( . { . last = true } ) ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, .a11y = __yix_view_ctx.a11y, }, ui.view.box(.{ .style = S.SettingRow.of(.{ .last = true }), }, .{
                    ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Status", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . setting_line ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, .a11y = __yix_view_ctx.a11y, }, ui.view.box(.{ .style = S.setting_line, }, .{
                        ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Status", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . setting_copy ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, ui.view.box(.{ .style = S.setting_copy, }, .{
                            ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Status", .receiver = "text", .tokens = "text style = @static; vm . pluginToggleLabel ( index )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . setting_label ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, ui.view.text(.{ .style = S.setting_label, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d4: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().pluginToggleLabel(__yix_view_ctx.index.peek()));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().pluginToggleLabel(__yix_ctx.index.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d4: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().pluginToggleLabel(__yix_view_ctx.index.peek()));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().pluginToggleLabel(__yix_ctx.index.get());
        } }.__yix_compute);
    }, }))),
                            ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Status", .receiver = "text", .tokens = "text testId = pid ( vm , index , . enabled_hint ) ; style = @static; box = P . toggle_hint_box ; D . toggle_hint  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "pid ( vm , index , . enabled_hint ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . setting_hint ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "P . toggle_hint_box ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, ui.view.text(.{ .test_id = __yix_d5: {
        const __yix_T = @TypeOf(pid(__yix_view_ctx.vm.peek(), __yix_view_ctx.index.peek(), .enabled_hint));
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return pid(__yix_ctx.vm.get(), __yix_ctx.index.get(), .enabled_hint);
        } }.__yix_compute);
    }, .style = S.setting_hint, .box = P.toggle_hint_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(D.toggle_hint), ""), .{ D.toggle_hint, }))),
                        })),
                        ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Status", .receiver = "W.Switch", .tokens = "< W . Switch testId = { pid ( vm , index , . enabled ) } checked = { vm . pluginEnabledDraft ( index ) } disabled = { vm . isSaving ( ) } a11y = { a11y } onChange = { | v | setEnabled ( vm , index , v ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "pid ( vm , index , . enabled ) ", .kind = .property, .literal = null }, .{ .name = "checked", .tokens = "vm . pluginEnabledDraft ( index ) ", .kind = .property, .literal = null }, .{ .name = "disabled", .tokens = "vm . isSaving ( ) ", .kind = .property, .literal = null }, .{ .name = "a11y", .tokens = "a11y ", .kind = .property, .literal = null }, .{ .name = "on_change", .tokens = "| v | setEnabled ( vm , index , v ) ", .kind = .event, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, .a11y = __yix_view_ctx.a11y, }, ui.view.templateAttrs(.{ .test_id = __yix_d6: {
        const __yix_T = if (ui.view.attrType(W.Switch, "test_id")) |__yix_A| __yix_A else @TypeOf(pid(__yix_view_ctx.vm.peek(), __yix_view_ctx.index.peek(), .enabled));
        break :__yix_d6 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return pid(__yix_ctx.vm.get(), __yix_ctx.index.get(), .enabled);
        } }.__yix_compute);
    }, .a11y = __yix_view_ctx.a11y, }, __yix_builder_9400: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Switch); break :__yix_builder_9400 W.Switch(.{ .checked = __yix_d7: {
        const __yix_T = if (ui.view.attrType(W.Switch, "checked")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().pluginEnabledDraft(__yix_view_ctx.index.peek()));
        break :__yix_d7 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().pluginEnabledDraft(__yix_ctx.index.get());
        } }.__yix_compute);
    }, .disabled = __yix_d8: {
        const __yix_T = if (ui.view.attrType(W.Switch, "disabled")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().isSaving());
        break :__yix_d8 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().isSaving();
        } }.__yix_compute);
    }, .on_change = ui.view.eventProp(W.Switch, "on_change", try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype, v: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); setEnabled(__yix_ctx.vm.peek(), __yix_ctx.index.peek(), v);  } }.__yix_run)), }); })),
                    })),
                    ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Status", .receiver = "text", .tokens = "text testId = pid ( vm , index , . enabled_error ) ; style = @static; visible = vm . pluginEnableInvalid ( index ) ; vm . pluginEnableProblem ( index )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "pid ( vm , index , . enabled_error ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . setting_error ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "vm . pluginEnableInvalid ( index ) ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, ui.view.text(.{ .test_id = __yix_d9: {
        const __yix_T = @TypeOf(pid(__yix_view_ctx.vm.peek(), __yix_view_ctx.index.peek(), .enabled_error));
        break :__yix_d9 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return pid(__yix_ctx.vm.get(), __yix_ctx.index.get(), .enabled_error);
        } }.__yix_compute);
    }, .style = S.setting_error, .visible = __yix_d10: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().pluginEnableInvalid(__yix_view_ctx.index.peek()));
        break :__yix_d10 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().pluginEnableInvalid(__yix_ctx.index.get());
        } }.__yix_compute);
    }, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d11: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().pluginEnableProblem(__yix_view_ctx.index.peek()));
        break :__yix_d11 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().pluginEnableProblem(__yix_ctx.index.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d11: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().pluginEnableProblem(__yix_view_ctx.index.peek()));
        break :__yix_d11 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().pluginEnableProblem(__yix_ctx.index.get());
        } }.__yix_compute);
    }, }))),
                })),
            })),
            ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Status", .receiver = "box", .tokens = "box testId = pid ( vm , index , . notice ) ; style = @static; visible = vm . pluginPending ( index ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "pid ( vm , index , . notice ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "P . notice ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "vm . pluginPending ( index ) ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, ui.view.box(.{ .test_id = __yix_d12: {
        const __yix_T = @TypeOf(pid(__yix_view_ctx.vm.peek(), __yix_view_ctx.index.peek(), .notice));
        break :__yix_d12 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return pid(__yix_ctx.vm.get(), __yix_ctx.index.get(), .notice);
        } }.__yix_compute);
    }, .style = P.notice, .visible = __yix_d13: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().pluginPending(__yix_view_ctx.index.peek()));
        break :__yix_d13 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().pluginPending(__yix_ctx.index.get());
        } }.__yix_compute);
    }, }, .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Status", .receiver = "W.Alert", .tokens = "< W . Alert variant = { . warning } title = { vm . pluginPendingTitle ( index ) } message = { vm . pluginPendingMessage ( index ) } actionLabel = { D . restart_label } actionIconAsset = { ui . icons . rotate_ccw } actionTestId = { pid ( vm , index , . restart ) } onAction = { restart ( vm ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "variant", .tokens = ". warning ", .kind = .property, .literal = .{ .enum_name = "warning" } }, .{ .name = "title", .tokens = "vm . pluginPendingTitle ( index ) ", .kind = .property, .literal = null }, .{ .name = "message", .tokens = "vm . pluginPendingMessage ( index ) ", .kind = .property, .literal = null }, .{ .name = "action_label", .tokens = "D . restart_label ", .kind = .property, .literal = null }, .{ .name = "action_icon_asset", .tokens = "ui . icons . rotate_ccw ", .kind = .property, .literal = null }, .{ .name = "action_test_id", .tokens = "pid ( vm , index , . restart ) ", .kind = .property, .literal = null }, .{ .name = "on_action", .tokens = "restart ( vm ) ", .kind = .event, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, __yix_builder_9919: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Alert); break :__yix_builder_9919 W.Alert(.{ .variant = .warning, .title = __yix_d14: {
        const __yix_T = if (ui.view.attrType(W.Alert, "title")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().pluginPendingTitle(__yix_view_ctx.index.peek()));
        break :__yix_d14 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().pluginPendingTitle(__yix_ctx.index.get());
        } }.__yix_compute);
    }, .message = __yix_d15: {
        const __yix_T = if (ui.view.attrType(W.Alert, "message")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().pluginPendingMessage(__yix_view_ctx.index.peek()));
        break :__yix_d15 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().pluginPendingMessage(__yix_ctx.index.get());
        } }.__yix_compute);
    }, .action_label = D.restart_label, .action_icon_asset = ui.icons.rotate_ccw, .action_test_id = __yix_d16: {
        const __yix_T = if (ui.view.attrType(W.Alert, "action_test_id")) |__yix_A| __yix_A else @TypeOf(pid(__yix_view_ctx.vm.peek(), __yix_view_ctx.index.peek(), .restart));
        break :__yix_d16 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return pid(__yix_ctx.vm.get(), __yix_ctx.index.get(), .restart);
        } }.__yix_compute);
    }, .on_action = if (comptime ui.view.isEventProp(W.Alert, "on_action")) try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); restart(__yix_ctx.vm.peek());  } }.__yix_run) else __yix_d17: {
        const __yix_T = if (ui.view.attrType(W.Alert, "on_action")) |__yix_A| __yix_A else @TypeOf(restart(__yix_view_ctx.vm.peek()));
        break :__yix_d17 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return restart(__yix_ctx.vm.get());
        } }.__yix_compute);
    }, }); }),
            })),
            ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Status", .receiver = "box", .tokens = "box testId = pid ( vm , index , . disabled ) ; style = @static; visible = vm . pluginDisabledShown ( index ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "pid ( vm , index , . disabled ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "P . notice ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "vm . pluginDisabledShown ( index ) ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, ui.view.box(.{ .test_id = __yix_d18: {
        const __yix_T = @TypeOf(pid(__yix_view_ctx.vm.peek(), __yix_view_ctx.index.peek(), .disabled));
        break :__yix_d18 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return pid(__yix_ctx.vm.get(), __yix_ctx.index.get(), .disabled);
        } }.__yix_compute);
    }, .style = P.notice, .visible = __yix_d19: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().pluginDisabledShown(__yix_view_ctx.index.peek()));
        break :__yix_d19 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().pluginDisabledShown(__yix_ctx.index.get());
        } }.__yix_compute);
    }, }, .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Status", .receiver = "W.Alert", .tokens = "< W . Alert variant = { . info } title = { vm . pluginDisabledTitle ( index ) } message = { vm . pluginDisabledMessage ( index ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "variant", .tokens = ". info ", .kind = .property, .literal = .{ .enum_name = "info" } }, .{ .name = "title", .tokens = "vm . pluginDisabledTitle ( index ) ", .kind = .property, .literal = null }, .{ .name = "message", .tokens = "vm . pluginDisabledMessage ( index ) ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, __yix_builder_10304: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Alert); break :__yix_builder_10304 W.Alert(.{ .variant = .info, .title = __yix_d20: {
        const __yix_T = if (ui.view.attrType(W.Alert, "title")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().pluginDisabledTitle(__yix_view_ctx.index.peek()));
        break :__yix_d20 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().pluginDisabledTitle(__yix_ctx.index.get());
        } }.__yix_compute);
    }, .message = __yix_d21: {
        const __yix_T = if (ui.view.attrType(W.Alert, "message")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().pluginDisabledMessage(__yix_view_ctx.index.peek()));
        break :__yix_d21 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().pluginDisabledMessage(__yix_ctx.index.get());
        } }.__yix_compute);
    }, }); }),
            })),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "Status";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

/// 权限的“?”：原生 ghost 图标按钮 + 原生 Tooltip（上方、450ms，悬停 / 聚焦 / 点击打开；整窗 Escape 先收起它）。
fn PermissionTip(args: anytype) ui.view.ComponentOf(__yix_PermissionTip) {
    return ui.view.component(__yix_PermissionTip, ui.reactive.props.coerce(PermissionTipProps, args));
}
const PermissionTipProps = struct {
    vm: ui.Source(*m.ViewModel),
    index: ui.Source(u8),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = PermissionTip;
    pub const __yix_preview_mount = __yix_PermissionTip;
};
fn __yix_PermissionTip(__yix_props: PermissionTipProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    const index = __yix_props.index;
    try ui.view.previewCheckSetup(scope, false);
    const tip = __yix_d1: {
        const __yix_T = @TypeOf(pid(vm.peek(), index.peek(), .permissions_tip));
        break :__yix_d1 try scope.derive(__yix_T, .{ .vm = vm, .index = index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return pid(__yix_ctx.vm.get(), __yix_ctx.index.get(), .permissions_tip);
        } }.__yix_compute);
    };
    const button = __yix_d2: {
        const __yix_T = @TypeOf(pid(vm.peek(), index.peek(), .permissions));
        break :__yix_d2 try scope.derive(__yix_T, .{ .vm = vm, .index = index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return pid(__yix_ctx.vm.get(), __yix_ctx.index.get(), .permissions);
        } }.__yix_compute);
    };
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, .index = index, .tip = tip, .button = button, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "PermissionTip", .receiver = "box", .tokens = "box style = @static; onFocus = setPopup ( vm , tip , true ) ; onBlur = setPopup ( vm , tip , false ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . help_slot ", .kind = .style, .literal = null }, .{ .name = "on_focus", .tokens = "setPopup ( vm , tip , true ) ", .kind = .event, .literal = null }, .{ .name = "on_blur", .tokens = "setPopup ( vm , tip , false ) ", .kind = .event, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .vm = __yix_view_ctx.vm, .tip = __yix_view_ctx.tip, .index = __yix_view_ctx.index, .button = __yix_view_ctx.button, }, ui.view.box(.{ .style = S.help_slot, .on_focus = try ui.on.bind(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .tip = __yix_view_ctx.tip, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); setPopup(__yix_ctx.vm.peek(), __yix_ctx.tip.peek(), true);  } }.__yix_run), .on_blur = try ui.on.bind(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .tip = __yix_view_ctx.tip, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); setPopup(__yix_ctx.vm.peek(), __yix_ctx.tip.peek(), false);  } }.__yix_run), }, .{
            ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "PermissionTip", .receiver = "W.Tooltip", .tokens = "< W . Tooltip text = { vm . pluginPermissions ( index ) } position = { . top } width = { 292 } open = { popup ( vm , tip ) } onOpenChange = { | o | setPopup ( vm , tip , o ) } parts = { . { . content = tip } } > < W . Button testId = { button } variant = { . ghost } size = { . xs } iconOnly = { true } iconAsset = { ui . icons . circle_help } iconSize = { 14 } a11yLabel = { vm . pluginPermissions ( index ) } onClick = { setPopup ( vm , tip , true ) } / > < / W . Tooltip > ", .literal_text = null, .attributes = &.{ .{ .name = "text", .tokens = "vm . pluginPermissions ( index ) ", .kind = .property, .literal = null }, .{ .name = "position", .tokens = ". top ", .kind = .property, .literal = .{ .enum_name = "top" } }, .{ .name = "width", .tokens = "292 ", .kind = .property, .literal = .{ .number = 292 } }, .{ .name = "open", .tokens = "popup ( vm , tip ) ", .kind = .property, .literal = null }, .{ .name = "on_open_change", .tokens = "| o | setPopup ( vm , tip , o ) ", .kind = .event, .literal = null }, .{ .name = "parts", .tokens = ". { . content = tip } ", .kind = .property, .literal = null }, } }, .{ .tip = __yix_view_ctx.tip, .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, .button = __yix_view_ctx.button, }, ui.view.templateAttrs(.{ .parts = .{ .content = __yix_view_ctx.tip }, }, __yix_builder_10906: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Tooltip); break :__yix_builder_10906 ui.view.with(W.Tooltip(.{ .text = __yix_d3: {
        const __yix_T = if (ui.view.attrType(W.Tooltip, "text")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().pluginPermissions(__yix_view_ctx.index.peek()));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().pluginPermissions(__yix_ctx.index.get());
        } }.__yix_compute);
    }, .position = .top, .width = 292, .open = __yix_d4: {
        const __yix_T = if (ui.view.attrType(W.Tooltip, "open")) |__yix_A| __yix_A else @TypeOf(popup(__yix_view_ctx.vm.peek(), __yix_view_ctx.tip.peek()));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .tip = __yix_view_ctx.tip, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return popup(__yix_ctx.vm.get(), __yix_ctx.tip.get());
        } }.__yix_compute);
    }, .on_open_change = ui.view.eventProp(W.Tooltip, "on_open_change", try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .tip = __yix_view_ctx.tip, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype, o: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); setPopup(__yix_ctx.vm.peek(), __yix_ctx.tip.peek(), o);  } }.__yix_run)), }), .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "PermissionTip", .receiver = "W.Button", .tokens = "< W . Button testId = { button } variant = { . ghost } size = { . xs } iconOnly = { true } iconAsset = { ui . icons . circle_help } iconSize = { 14 } a11yLabel = { vm . pluginPermissions ( index ) } onClick = { setPopup ( vm , tip , true ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "button ", .kind = .property, .literal = null }, .{ .name = "variant", .tokens = ". ghost ", .kind = .property, .literal = .{ .enum_name = "ghost" } }, .{ .name = "size", .tokens = ". xs ", .kind = .property, .literal = .{ .enum_name = "xs" } }, .{ .name = "icon_only", .tokens = "true ", .kind = .property, .literal = .{ .boolean = true } }, .{ .name = "icon_asset", .tokens = "ui . icons . circle_help ", .kind = .property, .literal = null }, .{ .name = "icon_size", .tokens = "14 ", .kind = .property, .literal = .{ .number = 14 } }, .{ .name = "a11y_label", .tokens = "vm . pluginPermissions ( index ) ", .kind = .property, .literal = null }, .{ .name = "on_click", .tokens = "setPopup ( vm , tip , true ) ", .kind = .event, .literal = null }, } }, .{ .button = __yix_view_ctx.button, .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, .tip = __yix_view_ctx.tip, }, ui.view.templateAttrs(.{ .test_id = __yix_view_ctx.button, }, __yix_builder_11087: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_11087 W.Button(.{ .variant = .ghost, .size = .xs, .icon_only = true, .icon_asset = ui.icons.circle_help, .icon_size = 14, .a11y_label = __yix_d5: {
        const __yix_T = if (ui.view.attrType(W.Button, "a11y_label")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().pluginPermissions(__yix_view_ctx.index.peek()));
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().pluginPermissions(__yix_ctx.index.get());
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
    __yix_root.meta.ownership.meta.component_name = "PermissionTip";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

/// 插件信息：版本、权限（旧详情的事实行；版本对话框的“插件随应用更新”在概要的管理说明里）。
fn Facts(args: anytype) ui.view.ComponentOf(__yix_Facts) {
    return ui.view.component(__yix_Facts, ui.reactive.props.coerce(FactsProps, args));
}
const FactsProps = struct {
    vm: ui.Source(*m.ViewModel),
    index: ui.Source(u8),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = Facts;
    pub const __yix_preview_mount = __yix_Facts;
};
fn __yix_Facts(__yix_props: FactsProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    const index = __yix_props.index;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, .index = index, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Facts", .receiver = "box", .tokens = "box testId = @static; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"settings.plugins.info\" ", .kind = .property, .literal = .{ .text = "settings.plugins.info" } }, .{ .name = "style", .tokens = "S . pane ", .kind = .style, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, ui.view.box(.{ .test_id = "settings.plugins.info", .style = S.pane, }, .{
            ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Facts", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . pane_header ", .kind = .style, .literal = null }, } }, .{ }, ui.view.box(.{ .style = S.pane_header, }, .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Facts", .receiver = "text", .tokens = "text style = @static; ", .literal_text = "插件信息", .attributes = &.{ .{ .name = "style", .tokens = "S . pane_title ", .kind = .style, .literal = null }, } }, .{ }, ui.view.text(.{ .style = S.pane_title, }, ui.view.fmt("插件信息", .{ }))),
            })),
            ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Facts", .receiver = "box", .tokens = "box testId = vm . pluginBodyId ( index ) ; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "vm . pluginBodyId ( index ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . pane_body ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, ui.view.box(.{ .test_id = __yix_d1: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().pluginBodyId(__yix_view_ctx.index.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().pluginBodyId(__yix_ctx.index.get());
        } }.__yix_compute);
    }, .style = S.pane_body, }, .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Facts", .receiver = "box", .tokens = "box style = S . SettingRow . of ( . { . last = false } ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . SettingRow . of ( . { . last = false } ) ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, ui.view.box(.{ .style = S.SettingRow.of(.{ .last = false }), }, .{
                    ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Facts", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . setting_line ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, ui.view.box(.{ .style = S.setting_line, }, .{
                        ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Facts", .receiver = "text", .tokens = "text style = @static; box = S . info_label_box ; ", .literal_text = "版本", .attributes = &.{ .{ .name = "style", .tokens = "S . setting_label ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . info_label_box ", .kind = .property, .literal = null }, } }, .{ }, ui.view.text(.{ .style = S.setting_label, .box = S.info_label_box, }, ui.view.fmt("版本", .{ }))),
                        ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Facts", .receiver = "text", .tokens = "text testId = pid ( vm , index , . version ) ; style = @static; box = S . info_value_box ; vm . pluginVersion ( index )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "pid ( vm , index , . version ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . info_value ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . info_value_box ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, ui.view.text(.{ .test_id = __yix_d2: {
        const __yix_T = @TypeOf(pid(__yix_view_ctx.vm.peek(), __yix_view_ctx.index.peek(), .version));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return pid(__yix_ctx.vm.get(), __yix_ctx.index.get(), .version);
        } }.__yix_compute);
    }, .style = S.info_value, .box = S.info_value_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d3: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().pluginVersion(__yix_view_ctx.index.peek()));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().pluginVersion(__yix_ctx.index.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d3: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().pluginVersion(__yix_view_ctx.index.peek()));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().pluginVersion(__yix_ctx.index.get());
        } }.__yix_compute);
    }, }))),
                    })),
                })),
                ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Facts", .receiver = "box", .tokens = "box style = S . SettingRow . of ( . { . last = true } ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . SettingRow . of ( . { . last = true } ) ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, ui.view.box(.{ .style = S.SettingRow.of(.{ .last = true }), }, .{
                    ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Facts", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . setting_line ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, ui.view.box(.{ .style = S.setting_line, }, .{
                        ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Facts", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . setting_heading ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, ui.view.box(.{ .style = S.setting_heading, }, .{
                            ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Facts", .receiver = "text", .tokens = "text style = @static; ", .literal_text = "权限", .attributes = &.{ .{ .name = "style", .tokens = "S . setting_label ", .kind = .style, .literal = null }, } }, .{ }, ui.view.text(.{ .style = S.setting_label, }, ui.view.fmt("权限", .{ }))),
                            ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Facts", .receiver = "PermissionTip", .tokens = "< PermissionTip vm = { vm } index = { index } / > ", .literal_text = null, .attributes = &.{ .{ .name = "vm", .tokens = "vm ", .kind = .property, .literal = null }, .{ .name = "index", .tokens = "index ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, __yix_builder_12448: { try ui.view.previewCheckBuilder(__yix_view_scope, PermissionTip); break :__yix_builder_12448 PermissionTip(.{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }); }),
                        })),
                        ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Facts", .receiver = "text", .tokens = "text testId = pid ( vm , index , . permissions_value ) ; style = @static; box = S . info_value_box ; D . permissions_value  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "pid ( vm , index , . permissions_value ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . info_value ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . info_value_box ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, ui.view.text(.{ .test_id = __yix_d4: {
        const __yix_T = @TypeOf(pid(__yix_view_ctx.vm.peek(), __yix_view_ctx.index.peek(), .permissions_value));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return pid(__yix_ctx.vm.get(), __yix_ctx.index.get(), .permissions_value);
        } }.__yix_compute);
    }, .style = S.info_value, .box = S.info_value_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(D.permissions_value), ""), .{ D.permissions_value, }))),
                    })),
                })),
            })),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "Facts";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

// ── 偏好字段 ──

fn prefs(vm: *m.ViewModel, index: u8) []const m.PluginPrefItem {
    return vm.pluginPrefItems(index);
}
fn hasPrefs(vm: *m.ViewModel, index: u8) bool {
    return vm.pluginHasPrefs(index);
}
fn fid(vm: *m.ViewModel, index: u8, field: u8, part: m.PluginPrefPart) []const u8 {
    return vm.pluginPrefId(index, field, part);
}
fn isKind(vm: *m.ViewModel, index: u8, field: u8, kind: m.PluginPrefKind) bool {
    return vm.pluginPrefKind(index, field) == kind;
}
fn timingIcon(vm: *m.ViewModel, index: u8, field: u8) ?ui.SvgAsset {
    return if (vm.pluginPrefNextConnection(index, field)) ui.icons.clock_3 else ui.icons.circle_check;
}
fn boolText(value: bool) []const u8 {
    return if (value) "true" else "false";
}
fn setBool(vm: *m.ViewModel, index: u8, field: u8, value: bool) void {
    vm.dispatch(m.Intent.setPluginPreference(index, field, boolText(value)));
}
fn setText(vm: *m.ViewModel, index: u8, field: u8, text: []const u8) void {
    vm.dispatch(m.Intent.setPluginPreference(index, field, text));
}
fn pick(vm: *m.ViewModel, index: u8, field: u8, value: ?[]const u8) void {
    vm.dispatch(m.Intent.setPluginPreference(index, field, value orelse return));
}
fn switchA11y(vm: *m.ViewModel, index: u8, field: u8) ?ui.A11yProps {
    return .{ .role = .switch_role, .label = vm.pluginPrefLabel(index, field), .checked = vm.pluginPrefChecked(index, field), .disabled = vm.isSaving() };
}
fn selectValue(vm: *m.ViewModel, index: u8, field: u8) ?[]const u8 {
    return vm.pluginPrefText(index, field);
}
/// 选择框的选项（注册表里的选项换成原生 `W.SelectOption`；一个详情页同时只挂一个插件的字段，按字段分槽）。
var option_buffer: [D.max_preferences][D.max_options]W.SelectOption = undefined;
fn options(vm: *m.ViewModel, index: u8, field: u8) []const W.SelectOption {
    const count = vm.pluginPrefOptionCount(index, field);
    const list = &option_buffer[field];
    for (0..count) |option| list[option] = .{ .value = vm.pluginPrefOptionValue(index, field, option), .label = vm.pluginPrefOptionLabel(index, field, option) };
    return list[0..count];
}

/// 生效时机：原生 ghost 图标按钮 + 原生 Tooltip（“下次连接生效” / “保存后生效”；同旧 `controls.inlineHint`）。
fn TimingTip(args: anytype) ui.view.ComponentOf(__yix_TimingTip) {
    return ui.view.component(__yix_TimingTip, ui.reactive.props.coerce(TimingTipProps, args));
}
const TimingTipProps = struct {
    vm: ui.Source(*m.ViewModel),
    index: ui.Source(u8),
    field: ui.Source(u8),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = TimingTip;
    pub const __yix_preview_mount = __yix_TimingTip;
};
fn __yix_TimingTip(__yix_props: TimingTipProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    const index = __yix_props.index;
    const field = __yix_props.field;
    try ui.view.previewCheckSetup(scope, false);
    const tip = __yix_d1: {
        const __yix_T = @TypeOf(fid(vm.peek(), index.peek(), field.peek(), .timing_tip));
        break :__yix_d1 try scope.derive(__yix_T, .{ .vm = vm, .index = index, .field = field, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return fid(__yix_ctx.vm.get(), __yix_ctx.index.get(), __yix_ctx.field.get(), .timing_tip);
        } }.__yix_compute);
    };
    const button = __yix_d2: {
        const __yix_T = @TypeOf(fid(vm.peek(), index.peek(), field.peek(), .timing));
        break :__yix_d2 try scope.derive(__yix_T, .{ .vm = vm, .index = index, .field = field, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return fid(__yix_ctx.vm.get(), __yix_ctx.index.get(), __yix_ctx.field.get(), .timing);
        } }.__yix_compute);
    };
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, .index = index, .field = field, .tip = tip, .button = button, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "TimingTip", .receiver = "box", .tokens = "box style = @static; onFocus = setPopup ( vm , tip , true ) ; onBlur = setPopup ( vm , tip , false ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . help_slot ", .kind = .style, .literal = null }, .{ .name = "on_focus", .tokens = "setPopup ( vm , tip , true ) ", .kind = .event, .literal = null }, .{ .name = "on_blur", .tokens = "setPopup ( vm , tip , false ) ", .kind = .event, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .vm = __yix_view_ctx.vm, .tip = __yix_view_ctx.tip, .index = __yix_view_ctx.index, .field = __yix_view_ctx.field, .button = __yix_view_ctx.button, }, ui.view.box(.{ .style = S.help_slot, .on_focus = try ui.on.bind(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .tip = __yix_view_ctx.tip, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); setPopup(__yix_ctx.vm.peek(), __yix_ctx.tip.peek(), true);  } }.__yix_run), .on_blur = try ui.on.bind(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .tip = __yix_view_ctx.tip, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); setPopup(__yix_ctx.vm.peek(), __yix_ctx.tip.peek(), false);  } }.__yix_run), }, .{
            ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "TimingTip", .receiver = "W.Tooltip", .tokens = "< W . Tooltip text = { vm . pluginPrefTiming ( index , field ) } position = { . top } open = { popup ( vm , tip ) } onOpenChange = { | o | setPopup ( vm , tip , o ) } parts = { . { . content = tip } } > < W . Button testId = { button } variant = { . ghost } size = { . xs } iconOnly = { true } iconAsset = { timingIcon ( vm , index , field ) } iconSize = { 14 } a11yLabel = { vm . pluginPrefTiming ( index , field ) } onClick = { setPopup ( vm , tip , true ) } / > < / W . Tooltip > ", .literal_text = null, .attributes = &.{ .{ .name = "text", .tokens = "vm . pluginPrefTiming ( index , field ) ", .kind = .property, .literal = null }, .{ .name = "position", .tokens = ". top ", .kind = .property, .literal = .{ .enum_name = "top" } }, .{ .name = "open", .tokens = "popup ( vm , tip ) ", .kind = .property, .literal = null }, .{ .name = "on_open_change", .tokens = "| o | setPopup ( vm , tip , o ) ", .kind = .event, .literal = null }, .{ .name = "parts", .tokens = ". { . content = tip } ", .kind = .property, .literal = null }, } }, .{ .tip = __yix_view_ctx.tip, .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, .field = __yix_view_ctx.field, .button = __yix_view_ctx.button, }, ui.view.templateAttrs(.{ .parts = .{ .content = __yix_view_ctx.tip }, }, __yix_builder_15364: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Tooltip); break :__yix_builder_15364 ui.view.with(W.Tooltip(.{ .text = __yix_d3: {
        const __yix_T = if (ui.view.attrType(W.Tooltip, "text")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().pluginPrefTiming(__yix_view_ctx.index.peek(), __yix_view_ctx.field.peek()));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, .field = __yix_view_ctx.field, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().pluginPrefTiming(__yix_ctx.index.get(), __yix_ctx.field.get());
        } }.__yix_compute);
    }, .position = .top, .open = __yix_d4: {
        const __yix_T = if (ui.view.attrType(W.Tooltip, "open")) |__yix_A| __yix_A else @TypeOf(popup(__yix_view_ctx.vm.peek(), __yix_view_ctx.tip.peek()));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .tip = __yix_view_ctx.tip, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return popup(__yix_ctx.vm.get(), __yix_ctx.tip.get());
        } }.__yix_compute);
    }, .on_open_change = ui.view.eventProp(W.Tooltip, "on_open_change", try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .tip = __yix_view_ctx.tip, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype, o: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); setPopup(__yix_ctx.vm.peek(), __yix_ctx.tip.peek(), o);  } }.__yix_run)), }), .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "TimingTip", .receiver = "W.Button", .tokens = "< W . Button testId = { button } variant = { . ghost } size = { . xs } iconOnly = { true } iconAsset = { timingIcon ( vm , index , field ) } iconSize = { 14 } a11yLabel = { vm . pluginPrefTiming ( index , field ) } onClick = { setPopup ( vm , tip , true ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "button ", .kind = .property, .literal = null }, .{ .name = "variant", .tokens = ". ghost ", .kind = .property, .literal = .{ .enum_name = "ghost" } }, .{ .name = "size", .tokens = ". xs ", .kind = .property, .literal = .{ .enum_name = "xs" } }, .{ .name = "icon_only", .tokens = "true ", .kind = .property, .literal = .{ .boolean = true } }, .{ .name = "icon_asset", .tokens = "timingIcon ( vm , index , field ) ", .kind = .property, .literal = null }, .{ .name = "icon_size", .tokens = "14 ", .kind = .property, .literal = .{ .number = 14 } }, .{ .name = "a11y_label", .tokens = "vm . pluginPrefTiming ( index , field ) ", .kind = .property, .literal = null }, .{ .name = "on_click", .tokens = "setPopup ( vm , tip , true ) ", .kind = .event, .literal = null }, } }, .{ .button = __yix_view_ctx.button, .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, .field = __yix_view_ctx.field, .tip = __yix_view_ctx.tip, }, ui.view.templateAttrs(.{ .test_id = __yix_view_ctx.button, }, __yix_builder_15539: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_15539 W.Button(.{ .variant = .ghost, .size = .xs, .icon_only = true, .icon_asset = __yix_d5: {
        const __yix_T = if (ui.view.attrType(W.Button, "icon_asset")) |__yix_A| __yix_A else @TypeOf(timingIcon(__yix_view_ctx.vm.peek(), __yix_view_ctx.index.peek(), __yix_view_ctx.field.peek()));
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, .field = __yix_view_ctx.field, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return timingIcon(__yix_ctx.vm.get(), __yix_ctx.index.get(), __yix_ctx.field.get());
        } }.__yix_compute);
    }, .icon_size = 14, .a11y_label = __yix_d6: {
        const __yix_T = if (ui.view.attrType(W.Button, "a11y_label")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().pluginPrefTiming(__yix_view_ctx.index.peek(), __yix_view_ctx.field.peek()));
        break :__yix_d6 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, .field = __yix_view_ctx.field, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().pluginPrefTiming(__yix_ctx.index.get(), __yix_ctx.field.get());
        } }.__yix_compute);
    }, .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .tip = __yix_view_ctx.tip, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); setPopup(__yix_ctx.vm.peek(), __yix_ctx.tip.peek(), true);  } }.__yix_run) else __yix_d7: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(setPopup(__yix_view_ctx.vm.peek(), __yix_view_ctx.tip.peek(), true));
        break :__yix_d7 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .tip = __yix_view_ctx.tip, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return setPopup(__yix_ctx.vm.get(), __yix_ctx.tip.get(), true);
        } }.__yix_compute);
    }, }); })),
            }); })),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "TimingTip";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

/// 一个偏好字段行：标签 + 生效时机，右侧是按字段类型的原生控件；被拒绝的编辑在行下提示原因。
fn PrefRow(args: anytype) ui.view.ComponentOf(__yix_PrefRow) {
    return ui.view.component(__yix_PrefRow, ui.reactive.props.coerce(PrefRowProps, args));
}
const PrefRowProps = struct {
    vm: ui.Source(*m.ViewModel),
    index: ui.Source(u8),
    field: ui.Source(u8),
    last: ui.Source(bool),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = PrefRow;
    pub const __yix_preview_mount = __yix_PrefRow;
};
fn __yix_PrefRow(__yix_props: PrefRowProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    const index = __yix_props.index;
    const field = __yix_props.field;
    const last = __yix_props.last;
    try ui.view.previewCheckSetup(scope, false);
    const control = __yix_d1: {
        const __yix_T = @TypeOf(fid(vm.peek(), index.peek(), field.peek(), .control));
        break :__yix_d1 try scope.derive(__yix_T, .{ .vm = vm, .index = index, .field = field, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return fid(__yix_ctx.vm.get(), __yix_ctx.index.get(), __yix_ctx.field.get(), .control);
        } }.__yix_compute);
    };
    const switch_a11y = __yix_d2: {
        const __yix_T = @TypeOf(switchA11y(vm.peek(), index.peek(), field.peek()));
        break :__yix_d2 try scope.derive(__yix_T, .{ .vm = vm, .index = index, .field = field, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return switchA11y(__yix_ctx.vm.get(), __yix_ctx.index.get(), __yix_ctx.field.get());
        } }.__yix_compute);
    };
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, .index = index, .field = field, .last = last, .control = control, .switch_a11y = switch_a11y, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "PrefRow", .receiver = "box", .tokens = "box testId = fid ( vm , index , field , . row ) ; style = S . SettingRow . of ( . { . last = last } ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "fid ( vm , index , field , . row ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . SettingRow . of ( . { . last = last } ) ", .kind = .style, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, .field = __yix_view_ctx.field, .last = __yix_view_ctx.last, .control = __yix_view_ctx.control, .switch_a11y = __yix_view_ctx.switch_a11y, }, ui.view.box(.{ .test_id = __yix_d3: {
        const __yix_T = @TypeOf(fid(__yix_view_ctx.vm.peek(), __yix_view_ctx.index.peek(), __yix_view_ctx.field.peek(), .row));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, .field = __yix_view_ctx.field, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return fid(__yix_ctx.vm.get(), __yix_ctx.index.get(), __yix_ctx.field.get(), .row);
        } }.__yix_compute);
    }, .style = S.SettingRow.of(.{ .last = __yix_view_ctx.last }), }, .{
            ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "PrefRow", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . setting_line ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, .field = __yix_view_ctx.field, .control = __yix_view_ctx.control, .switch_a11y = __yix_view_ctx.switch_a11y, }, ui.view.box(.{ .style = S.setting_line, }, .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "PrefRow", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . setting_copy ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, .field = __yix_view_ctx.field, }, ui.view.box(.{ .style = S.setting_copy, }, .{
                    ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "PrefRow", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . setting_heading ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, .field = __yix_view_ctx.field, }, ui.view.box(.{ .style = S.setting_heading, }, .{
                        ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "PrefRow", .receiver = "text", .tokens = "text style = @static; vm . pluginPrefLabel ( index , field )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . setting_label ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, .field = __yix_view_ctx.field, }, ui.view.text(.{ .style = S.setting_label, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d4: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().pluginPrefLabel(__yix_view_ctx.index.peek(), __yix_view_ctx.field.peek()));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, .field = __yix_view_ctx.field, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().pluginPrefLabel(__yix_ctx.index.get(), __yix_ctx.field.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d4: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().pluginPrefLabel(__yix_view_ctx.index.peek(), __yix_view_ctx.field.peek()));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, .field = __yix_view_ctx.field, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().pluginPrefLabel(__yix_ctx.index.get(), __yix_ctx.field.get());
        } }.__yix_compute);
    }, }))),
                        ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "PrefRow", .receiver = "TimingTip", .tokens = "< TimingTip vm = { vm } index = { index } field = { field } / > ", .literal_text = null, .attributes = &.{ .{ .name = "vm", .tokens = "vm ", .kind = .property, .literal = null }, .{ .name = "index", .tokens = "index ", .kind = .property, .literal = null }, .{ .name = "field", .tokens = "field ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, .field = __yix_view_ctx.field, }, __yix_builder_16496: { try ui.view.previewCheckBuilder(__yix_view_scope, TimingTip); break :__yix_builder_16496 TimingTip(.{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, .field = __yix_view_ctx.field, }); }),
                    })),
                })),
                ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "PrefRow", .receiver = "control", .tokens = "if ( isKind ( vm , index , field , . boolean ) ) < W . Switch testId = { control } checked = { vm . pluginPrefChecked ( index , field ) } disabled = { vm . isSaving ( ) } a11y = { switch_a11y } onChange = { | v | setBool ( vm , index , field , v ) } / > else if ( isKind ( vm , index , field , . string ) ) < W . Input value = { vm . pluginPrefText ( index , field ) } width = { 180 } invalid = { vm . pluginPrefInvalid ( index , field ) } disabled = { vm . isSaving ( ) } onChange = { | t | setText ( vm , index , field , t ) } onSubmit = { | t | setText ( vm , index , field , t ) } parts = { . { . input_container = control } } / > else < W . Select panelWidth = { . trigger } options = { options ( vm , index , field ) } value = { selectValue ( vm , index , field ) } width = { 180 } disabled = { vm . isSaving ( ) } open = { popup ( vm , control ) } onOpenChange = { | o | setPopup ( vm , control , o ) } onChange = { | v | pick ( vm , index , field , v ) } parts = { . { . trigger = control } } / > " }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, .field = __yix_view_ctx.field, .control = __yix_view_ctx.control, .switch_a11y = __yix_view_ctx.switch_a11y, }, ui.view.lazyIf(__yix_d11: {
        const __yix_T = @TypeOf(isKind(__yix_view_ctx.vm.peek(), __yix_view_ctx.index.peek(), __yix_view_ctx.field.peek(), .boolean));
        break :__yix_d11 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, .field = __yix_view_ctx.field, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return isKind(__yix_ctx.vm.get(), __yix_ctx.index.get(), __yix_ctx.field.get(), .boolean);
        } }.__yix_compute);
    }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, .field = __yix_view_ctx.field, .control = __yix_view_ctx.control, .switch_a11y = __yix_view_ctx.switch_a11y, }, struct { fn __yix_b(__yix_b1_0: anytype, __yix_bs1_0: *ui.Scope, __yix_bc1_0: *ui.Cx, __yix_bk1_0: ui.view.Sink) anyerror!void { return ui.view.emit(__yix_bs1_0, __yix_bc1_0, __yix_bk1_0, .{ ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "PrefRow/keyword_if:1/branch:0", .receiver = "W.Switch", .tokens = "< W . Switch testId = { control } checked = { vm . pluginPrefChecked ( index , field ) } disabled = { vm . isSaving ( ) } a11y = { switch_a11y } onChange = { | v | setBool ( vm , index , field , v ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "control ", .kind = .property, .literal = null }, .{ .name = "checked", .tokens = "vm . pluginPrefChecked ( index , field ) ", .kind = .property, .literal = null }, .{ .name = "disabled", .tokens = "vm . isSaving ( ) ", .kind = .property, .literal = null }, .{ .name = "a11y", .tokens = "switch_a11y ", .kind = .property, .literal = null }, .{ .name = "on_change", .tokens = "| v | setBool ( vm , index , field , v ) ", .kind = .event, .literal = null }, } }, .{ .control = __yix_b1_0.control, .switch_a11y = __yix_b1_0.switch_a11y, .vm = __yix_b1_0.vm, .index = __yix_b1_0.index, .field = __yix_b1_0.field, }, ui.view.templateAttrs(.{ .test_id = __yix_b1_0.control, .a11y = __yix_b1_0.switch_a11y, }, __yix_builder_40: { try ui.view.previewCheckBuilder(__yix_bs1_0, W.Switch); break :__yix_builder_40 W.Switch(.{ .checked = __yix_d1: {
        const __yix_T = if (ui.view.attrType(W.Switch, "checked")) |__yix_A| __yix_A else @TypeOf(__yix_b1_0.vm.peek().pluginPrefChecked(__yix_b1_0.index.peek(), __yix_b1_0.field.peek()));
        break :__yix_d1 try __yix_bs1_0.derive(__yix_T, .{ .vm = __yix_b1_0.vm, .index = __yix_b1_0.index, .field = __yix_b1_0.field, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().pluginPrefChecked(__yix_ctx.index.get(), __yix_ctx.field.get());
        } }.__yix_compute);
    }, .disabled = __yix_d2: {
        const __yix_T = if (ui.view.attrType(W.Switch, "disabled")) |__yix_A| __yix_A else @TypeOf(__yix_b1_0.vm.peek().isSaving());
        break :__yix_d2 try __yix_bs1_0.derive(__yix_T, .{ .vm = __yix_b1_0.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().isSaving();
        } }.__yix_compute);
    }, .on_change = ui.view.eventProp(W.Switch, "on_change", try ui.on.bindAny(__yix_bs1_0, .{ .vm = __yix_b1_0.vm, .index = __yix_b1_0.index, .field = __yix_b1_0.field, .__yix_owner = __yix_bs1_0.owner, }, struct { fn __yix_run(__yix_ctx: anytype, v: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); setBool(__yix_ctx.vm.peek(), __yix_ctx.index.peek(), __yix_ctx.field.peek(), v);  } }.__yix_run)), }); })) }); } }.__yix_b, struct { fn __yix_b(__yix_b1_1: anytype, __yix_bs1_1: *ui.Scope, __yix_bc1_1: *ui.Cx, __yix_bk1_1: ui.view.Sink) anyerror!void { return ui.view.emit(__yix_bs1_1, __yix_bc1_1, __yix_bk1_1, .{ ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "PrefRow/keyword_if:1/branch:1", .receiver = "control", .tokens = "if ( isKind ( vm , index , field , . string ) ) < W . Input value = { vm . pluginPrefText ( index , field ) } width = { 180 } invalid = { vm . pluginPrefInvalid ( index , field ) } disabled = { vm . isSaving ( ) } onChange = { | t | setText ( vm , index , field , t ) } onSubmit = { | t | setText ( vm , index , field , t ) } parts = { . { . input_container = control } } / > else < W . Select panelWidth = { . trigger } options = { options ( vm , index , field ) } value = { selectValue ( vm , index , field ) } width = { 180 } disabled = { vm . isSaving ( ) } open = { popup ( vm , control ) } onOpenChange = { | o | setPopup ( vm , control , o ) } onChange = { | v | pick ( vm , index , field , v ) } parts = { . { . trigger = control } } / > " }, .{ .vm = __yix_b1_1.vm, .index = __yix_b1_1.index, .field = __yix_b1_1.field, .control = __yix_b1_1.control, }, ui.view.lazyIf(__yix_d10: {
        const __yix_T = @TypeOf(isKind(__yix_b1_1.vm.peek(), __yix_b1_1.index.peek(), __yix_b1_1.field.peek(), .string));
        break :__yix_d10 try __yix_bs1_1.derive(__yix_T, .{ .vm = __yix_b1_1.vm, .index = __yix_b1_1.index, .field = __yix_b1_1.field, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return isKind(__yix_ctx.vm.get(), __yix_ctx.index.get(), __yix_ctx.field.get(), .string);
        } }.__yix_compute);
    }, .{ .vm = __yix_b1_1.vm, .index = __yix_b1_1.index, .field = __yix_b1_1.field, .control = __yix_b1_1.control, }, struct { fn __yix_b(__yix_b2_0: anytype, __yix_bs2_0: *ui.Scope, __yix_bc2_0: *ui.Cx, __yix_bk2_0: ui.view.Sink) anyerror!void { return ui.view.emit(__yix_bs2_0, __yix_bc2_0, __yix_bk2_0, .{ ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "PrefRow/keyword_if:1/branch:1/keyword_if:2/branch:0", .receiver = "W.Input", .tokens = "< W . Input value = { vm . pluginPrefText ( index , field ) } width = { 180 } invalid = { vm . pluginPrefInvalid ( index , field ) } disabled = { vm . isSaving ( ) } onChange = { | t | setText ( vm , index , field , t ) } onSubmit = { | t | setText ( vm , index , field , t ) } parts = { . { . input_container = control } } / > ", .literal_text = null, .attributes = &.{ .{ .name = "value", .tokens = "vm . pluginPrefText ( index , field ) ", .kind = .property, .literal = null }, .{ .name = "width", .tokens = "180 ", .kind = .property, .literal = .{ .number = 180 } }, .{ .name = "invalid", .tokens = "vm . pluginPrefInvalid ( index , field ) ", .kind = .property, .literal = null }, .{ .name = "disabled", .tokens = "vm . isSaving ( ) ", .kind = .property, .literal = null }, .{ .name = "on_change", .tokens = "| t | setText ( vm , index , field , t ) ", .kind = .event, .literal = null }, .{ .name = "on_submit", .tokens = "| t | setText ( vm , index , field , t ) ", .kind = .event, .literal = null }, .{ .name = "parts", .tokens = ". { . input_container = control } ", .kind = .property, .literal = null }, } }, .{ .control = __yix_b2_0.control, .vm = __yix_b2_0.vm, .index = __yix_b2_0.index, .field = __yix_b2_0.field, }, ui.view.templateAttrs(.{ .parts = .{ .input_container = __yix_b2_0.control }, }, __yix_builder_247: { try ui.view.previewCheckBuilder(__yix_bs2_0, W.Input); break :__yix_builder_247 W.Input(.{ .value = __yix_d3: {
        const __yix_T = if (ui.view.attrType(W.Input, "value")) |__yix_A| __yix_A else @TypeOf(__yix_b2_0.vm.peek().pluginPrefText(__yix_b2_0.index.peek(), __yix_b2_0.field.peek()));
        break :__yix_d3 try __yix_bs2_0.derive(__yix_T, .{ .vm = __yix_b2_0.vm, .index = __yix_b2_0.index, .field = __yix_b2_0.field, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().pluginPrefText(__yix_ctx.index.get(), __yix_ctx.field.get());
        } }.__yix_compute);
    }, .width = 180, .invalid = __yix_d4: {
        const __yix_T = if (ui.view.attrType(W.Input, "invalid")) |__yix_A| __yix_A else @TypeOf(__yix_b2_0.vm.peek().pluginPrefInvalid(__yix_b2_0.index.peek(), __yix_b2_0.field.peek()));
        break :__yix_d4 try __yix_bs2_0.derive(__yix_T, .{ .vm = __yix_b2_0.vm, .index = __yix_b2_0.index, .field = __yix_b2_0.field, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().pluginPrefInvalid(__yix_ctx.index.get(), __yix_ctx.field.get());
        } }.__yix_compute);
    }, .disabled = __yix_d5: {
        const __yix_T = if (ui.view.attrType(W.Input, "disabled")) |__yix_A| __yix_A else @TypeOf(__yix_b2_0.vm.peek().isSaving());
        break :__yix_d5 try __yix_bs2_0.derive(__yix_T, .{ .vm = __yix_b2_0.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().isSaving();
        } }.__yix_compute);
    }, .on_change = ui.view.eventProp(W.Input, "on_change", try ui.on.bindAny(__yix_bs2_0, .{ .vm = __yix_b2_0.vm, .index = __yix_b2_0.index, .field = __yix_b2_0.field, .__yix_owner = __yix_bs2_0.owner, }, struct { fn __yix_run(__yix_ctx: anytype, t: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); setText(__yix_ctx.vm.peek(), __yix_ctx.index.peek(), __yix_ctx.field.peek(), t);  } }.__yix_run)), .on_submit = ui.view.eventProp(W.Input, "on_submit", try ui.on.bindAny(__yix_bs2_0, .{ .vm = __yix_b2_0.vm, .index = __yix_b2_0.index, .field = __yix_b2_0.field, .__yix_owner = __yix_bs2_0.owner, }, struct { fn __yix_run(__yix_ctx: anytype, t: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); setText(__yix_ctx.vm.peek(), __yix_ctx.index.peek(), __yix_ctx.field.peek(), t);  } }.__yix_run)), }); })) }); } }.__yix_b, struct { fn __yix_b(__yix_b2_1: anytype, __yix_bs2_1: *ui.Scope, __yix_bc2_1: *ui.Cx, __yix_bk2_1: ui.view.Sink) anyerror!void { return ui.view.emit(__yix_bs2_1, __yix_bc2_1, __yix_bk2_1, .{ ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "PrefRow/keyword_if:1/branch:1/keyword_if:2/branch:1", .receiver = "W.Select", .tokens = "< W . Select panelWidth = { . trigger } options = { options ( vm , index , field ) } value = { selectValue ( vm , index , field ) } width = { 180 } disabled = { vm . isSaving ( ) } open = { popup ( vm , control ) } onOpenChange = { | o | setPopup ( vm , control , o ) } onChange = { | v | pick ( vm , index , field , v ) } parts = { . { . trigger = control } } / > ", .literal_text = null, .attributes = &.{ .{ .name = "panel_width", .tokens = ". trigger ", .kind = .property, .literal = .{ .enum_name = "trigger" } }, .{ .name = "options", .tokens = "options ( vm , index , field ) ", .kind = .property, .literal = null }, .{ .name = "value", .tokens = "selectValue ( vm , index , field ) ", .kind = .property, .literal = null }, .{ .name = "width", .tokens = "180 ", .kind = .property, .literal = .{ .number = 180 } }, .{ .name = "disabled", .tokens = "vm . isSaving ( ) ", .kind = .property, .literal = null }, .{ .name = "open", .tokens = "popup ( vm , control ) ", .kind = .property, .literal = null }, .{ .name = "on_open_change", .tokens = "| o | setPopup ( vm , control , o ) ", .kind = .event, .literal = null }, .{ .name = "on_change", .tokens = "| v | pick ( vm , index , field , v ) ", .kind = .event, .literal = null }, .{ .name = "parts", .tokens = ". { . trigger = control } ", .kind = .property, .literal = null }, } }, .{ .control = __yix_b2_1.control, .vm = __yix_b2_1.vm, .index = __yix_b2_1.index, .field = __yix_b2_1.field, }, ui.view.templateAttrs(.{ .parts = .{ .trigger = __yix_b2_1.control }, }, __yix_builder_514: { try ui.view.previewCheckBuilder(__yix_bs2_1, W.Select); break :__yix_builder_514 W.Select(.{ .panel_width = .trigger, .options = __yix_d6: {
        const __yix_T = if (ui.view.attrType(W.Select, "options")) |__yix_A| __yix_A else @TypeOf(options(__yix_b2_1.vm.peek(), __yix_b2_1.index.peek(), __yix_b2_1.field.peek()));
        break :__yix_d6 try __yix_bs2_1.derive(__yix_T, .{ .vm = __yix_b2_1.vm, .index = __yix_b2_1.index, .field = __yix_b2_1.field, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return options(__yix_ctx.vm.get(), __yix_ctx.index.get(), __yix_ctx.field.get());
        } }.__yix_compute);
    }, .value = __yix_d7: {
        const __yix_T = if (ui.view.attrType(W.Select, "value")) |__yix_A| __yix_A else @TypeOf(selectValue(__yix_b2_1.vm.peek(), __yix_b2_1.index.peek(), __yix_b2_1.field.peek()));
        break :__yix_d7 try __yix_bs2_1.derive(__yix_T, .{ .vm = __yix_b2_1.vm, .index = __yix_b2_1.index, .field = __yix_b2_1.field, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return selectValue(__yix_ctx.vm.get(), __yix_ctx.index.get(), __yix_ctx.field.get());
        } }.__yix_compute);
    }, .width = 180, .disabled = __yix_d8: {
        const __yix_T = if (ui.view.attrType(W.Select, "disabled")) |__yix_A| __yix_A else @TypeOf(__yix_b2_1.vm.peek().isSaving());
        break :__yix_d8 try __yix_bs2_1.derive(__yix_T, .{ .vm = __yix_b2_1.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().isSaving();
        } }.__yix_compute);
    }, .open = __yix_d9: {
        const __yix_T = if (ui.view.attrType(W.Select, "open")) |__yix_A| __yix_A else @TypeOf(popup(__yix_b2_1.vm.peek(), __yix_b2_1.control.peek()));
        break :__yix_d9 try __yix_bs2_1.derive(__yix_T, .{ .vm = __yix_b2_1.vm, .control = __yix_b2_1.control, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return popup(__yix_ctx.vm.get(), __yix_ctx.control.get());
        } }.__yix_compute);
    }, .on_open_change = ui.view.eventProp(W.Select, "on_open_change", try ui.on.bindAny(__yix_bs2_1, .{ .vm = __yix_b2_1.vm, .control = __yix_b2_1.control, .__yix_owner = __yix_bs2_1.owner, }, struct { fn __yix_run(__yix_ctx: anytype, o: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); setPopup(__yix_ctx.vm.peek(), __yix_ctx.control.peek(), o);  } }.__yix_run)), .on_change = ui.view.eventProp(W.Select, "on_change", try ui.on.bindAny(__yix_bs2_1, .{ .vm = __yix_b2_1.vm, .index = __yix_b2_1.index, .field = __yix_b2_1.field, .__yix_owner = __yix_bs2_1.owner, }, struct { fn __yix_run(__yix_ctx: anytype, v: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); pick(__yix_ctx.vm.peek(), __yix_ctx.index.peek(), __yix_ctx.field.peek(), v);  } }.__yix_run)), }); })) }); } }.__yix_b)) }); } }.__yix_b)),
            })),
            ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "PrefRow", .receiver = "text", .tokens = "text testId = fid ( vm , index , field , . err ) ; style = @static; visible = vm . pluginPrefInvalid ( index , field ) ; vm . pluginPrefProblem ( index , field )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "fid ( vm , index , field , . err ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . setting_error ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "vm . pluginPrefInvalid ( index , field ) ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, .field = __yix_view_ctx.field, }, ui.view.text(.{ .test_id = __yix_d5: {
        const __yix_T = @TypeOf(fid(__yix_view_ctx.vm.peek(), __yix_view_ctx.index.peek(), __yix_view_ctx.field.peek(), .err));
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, .field = __yix_view_ctx.field, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return fid(__yix_ctx.vm.get(), __yix_ctx.index.get(), __yix_ctx.field.get(), .err);
        } }.__yix_compute);
    }, .style = S.setting_error, .visible = __yix_d6: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().pluginPrefInvalid(__yix_view_ctx.index.peek(), __yix_view_ctx.field.peek()));
        break :__yix_d6 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, .field = __yix_view_ctx.field, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().pluginPrefInvalid(__yix_ctx.index.get(), __yix_ctx.field.get());
        } }.__yix_compute);
    }, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d7: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().pluginPrefProblem(__yix_view_ctx.index.peek(), __yix_view_ctx.field.peek()));
        break :__yix_d7 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, .field = __yix_view_ctx.field, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().pluginPrefProblem(__yix_ctx.index.get(), __yix_ctx.field.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d7: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().pluginPrefProblem(__yix_view_ctx.index.peek(), __yix_view_ctx.field.peek()));
        break :__yix_d7 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, .field = __yix_view_ctx.field, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().pluginPrefProblem(__yix_ctx.index.get(), __yix_ctx.field.get());
        } }.__yix_compute);
    }, }))),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "PrefRow";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

/// 插件自带的设置（旧详情面板里的偏好行）。
fn Preferences(args: anytype) ui.view.ComponentOf(__yix_Preferences) {
    return ui.view.component(__yix_Preferences, ui.reactive.props.coerce(PreferencesProps, args));
}
const PreferencesProps = struct {
    vm: ui.Source(*m.ViewModel),
    index: ui.Source(u8),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = Preferences;
    pub const __yix_preview_mount = __yix_Preferences;
};
fn __yix_Preferences(__yix_props: PreferencesProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    const index = __yix_props.index;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, .index = index, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Preferences", .receiver = "box", .tokens = "box testId = @static; style = @static; visible = hasPrefs ( vm , index ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"settings.plugins.preferences\" ", .kind = .property, .literal = .{ .text = "settings.plugins.preferences" } }, .{ .name = "style", .tokens = "S . pane ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "hasPrefs ( vm , index ) ", .kind = .property, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, ui.view.box(.{ .test_id = "settings.plugins.preferences", .style = S.pane, .visible = __yix_d1: {
        const __yix_T = @TypeOf(hasPrefs(__yix_view_ctx.vm.peek(), __yix_view_ctx.index.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return hasPrefs(__yix_ctx.vm.get(), __yix_ctx.index.get());
        } }.__yix_compute);
    }, }, .{
            ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Preferences", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . pane_header ", .kind = .style, .literal = null }, } }, .{ }, ui.view.box(.{ .style = S.pane_header, }, .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Preferences", .receiver = "text", .tokens = "text style = @static; ", .literal_text = "偏好设置", .attributes = &.{ .{ .name = "style", .tokens = "S . pane_title ", .kind = .style, .literal = null }, } }, .{ }, ui.view.text(.{ .style = S.pane_title, }, ui.view.fmt("偏好设置", .{ }))),
            })),
            ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Preferences", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . pane_body ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, ui.view.box(.{ .style = S.pane_body, }, .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Preferences", .receiver = "control", .tokens = "for ( prefs ( vm , index ) ) | item | < PrefRow key = { item . key } vm = { vm } index = { index } field = { item . field } last = { item . last } / > " }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, __yix_e1: { const __yix_items_1 = __yix_d3: {
        const __yix_T = @TypeOf(prefs(__yix_view_ctx.vm.peek(), __yix_view_ctx.index.peek()));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return prefs(__yix_ctx.vm.get(), __yix_ctx.index.get());
        } }.__yix_compute);
    }; break :__yix_e1 ui.view.eachWith(.{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, __yix_items_1, struct { fn __yix_k(item: ui.view.yixItem(@TypeOf(__yix_items_1))) u64 { return ui.view.keyOf(item.key); } }.__yix_k, struct { fn __yix_row(__yix_row_1: anytype, item: ui.Source(ui.view.yixItem(@TypeOf(__yix_items_1))), __yix_scope_1: *ui.Scope, __yix_cx_1: *ui.Cx) anyerror!*ui.Node { return ui.view.render(__yix_scope_1, __yix_cx_1, ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Preferences/keyword_for:1", .receiver = "PrefRow", .tokens = "< PrefRow key = { item . key } vm = { vm } index = { index } field = { item . field } last = { item . last } / > ", .literal_text = null, .attributes = &.{ .{ .name = "key", .tokens = "item . key ", .kind = .property, .literal = null }, .{ .name = "vm", .tokens = "vm ", .kind = .property, .literal = null }, .{ .name = "index", .tokens = "index ", .kind = .property, .literal = null }, .{ .name = "field", .tokens = "item . field ", .kind = .property, .literal = null }, .{ .name = "last", .tokens = "item . last ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_row_1.vm, .index = __yix_row_1.index, .item = item, }, __yix_builder_30: { try ui.view.previewCheckBuilder(__yix_scope_1, PrefRow); break :__yix_builder_30 PrefRow(.{ .vm = __yix_row_1.vm, .index = __yix_row_1.index, .field = __yix_d1: {
        const __yix_T = if (ui.view.attrType(PrefRow, "field")) |__yix_A| __yix_A else @TypeOf(item.peek().field);
        break :__yix_d1 try __yix_scope_1.derive(__yix_T, .{ .item = item, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.item.get().field;
        } }.__yix_compute);
    }, .last = __yix_d2: {
        const __yix_T = if (ui.view.attrType(PrefRow, "last")) |__yix_A| __yix_A else @TypeOf(item.peek().last);
        break :__yix_d2 try __yix_scope_1.derive(__yix_T, .{ .item = item, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.item.get().last;
        } }.__yix_compute);
    }, }); })); } }.__yix_row); }),
            })),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "Preferences";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

fn Detail(args: anytype) ui.view.ComponentOf(__yix_Detail) {
    return ui.view.component(__yix_Detail, ui.reactive.props.coerce(DetailProps, args));
}
const DetailProps = struct {
    vm: ui.Source(*m.ViewModel),
    index: ui.Source(u8),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = Detail;
    pub const __yix_preview_mount = __yix_Detail;
};
fn __yix_Detail(__yix_props: DetailProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    const index = __yix_props.index;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, .index = index, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Detail", .receiver = "box", .tokens = "box testId = pid ( vm , index , . detail ) ; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "pid ( vm , index , . detail ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "P . panes ", .kind = .style, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, ui.view.box(.{ .test_id = __yix_d1: {
        const __yix_T = @TypeOf(pid(__yix_view_ctx.vm.peek(), __yix_view_ctx.index.peek(), .detail));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return pid(__yix_ctx.vm.get(), __yix_ctx.index.get(), .detail);
        } }.__yix_compute);
    }, .style = P.panes, }, .{
            ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Detail", .receiver = "Summary", .tokens = "< Summary vm = { vm } index = { index } / > ", .literal_text = null, .attributes = &.{ .{ .name = "vm", .tokens = "vm ", .kind = .property, .literal = null }, .{ .name = "index", .tokens = "index ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, __yix_builder_18326: { try ui.view.previewCheckBuilder(__yix_view_scope, Summary); break :__yix_builder_18326 Summary(.{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }); }),
            ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Detail", .receiver = "Status", .tokens = "< Status vm = { vm } index = { index } / > ", .literal_text = null, .attributes = &.{ .{ .name = "vm", .tokens = "vm ", .kind = .property, .literal = null }, .{ .name = "index", .tokens = "index ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, __yix_builder_18372: { try ui.view.previewCheckBuilder(__yix_view_scope, Status); break :__yix_builder_18372 Status(.{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }); }),
            ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Detail", .receiver = "Facts", .tokens = "< Facts vm = { vm } index = { index } / > ", .literal_text = null, .attributes = &.{ .{ .name = "vm", .tokens = "vm ", .kind = .property, .literal = null }, .{ .name = "index", .tokens = "index ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, __yix_builder_18417: { try ui.view.previewCheckBuilder(__yix_view_scope, Facts); break :__yix_builder_18417 Facts(.{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }); }),
            ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "Detail", .receiver = "Preferences", .tokens = "< Preferences vm = { vm } index = { index } / > ", .literal_text = null, .attributes = &.{ .{ .name = "vm", .tokens = "vm ", .kind = .property, .literal = null }, .{ .name = "index", .tokens = "index ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }, __yix_builder_18461: { try ui.view.previewCheckBuilder(__yix_view_scope, Preferences); break :__yix_builder_18461 Preferences(.{ .vm = __yix_view_ctx.vm, .index = __yix_view_ctx.index, }); }),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "Detail";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

pub fn PluginsPanes(args: anytype) ui.view.ComponentOf(__yix_PluginsPanes) {
    return ui.view.component(__yix_PluginsPanes, ui.reactive.props.coerce(PluginsPanesProps, args));
}
pub const PluginsPanesProps = struct {
    vm: ui.Source(*m.ViewModel),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = PluginsPanes;
    pub const __yix_preview_mount = __yix_PluginsPanes;
};
fn __yix_PluginsPanes(__yix_props: PluginsPanesProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "PluginsPanes", .receiver = "box", .tokens = "box testId = @static; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"settings.plugins\" ", .kind = .property, .literal = .{ .text = "settings.plugins" } }, .{ .name = "style", .tokens = "S . category_panes ", .kind = .style, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .vm = __yix_view_ctx.vm, }, ui.view.box(.{ .test_id = "settings.plugins", .style = S.category_panes, }, .{
            ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "PluginsPanes", .receiver = "control", .tokens = "if ( detailShown ( vm ) ) < Detail vm = { vm } index = { detailIndex ( vm ) } / > else < List vm = { vm } / > " }, .{ .vm = __yix_view_ctx.vm, }, ui.view.lazyIf(__yix_d2: {
        const __yix_T = @TypeOf(detailShown(__yix_view_ctx.vm.peek()));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return detailShown(__yix_ctx.vm.get());
        } }.__yix_compute);
    }, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_b(__yix_b1_0: anytype, __yix_bs1_0: *ui.Scope, __yix_bc1_0: *ui.Cx, __yix_bk1_0: ui.view.Sink) anyerror!void { return ui.view.emit(__yix_bs1_0, __yix_bc1_0, __yix_bk1_0, .{ ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "PluginsPanes/keyword_if:1/branch:0", .receiver = "Detail", .tokens = "< Detail vm = { vm } index = { detailIndex ( vm ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "vm", .tokens = "vm ", .kind = .property, .literal = null }, .{ .name = "index", .tokens = "detailIndex ( vm ) ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_b1_0.vm, }, __yix_builder_21: { try ui.view.previewCheckBuilder(__yix_bs1_0, Detail); break :__yix_builder_21 Detail(.{ .vm = __yix_b1_0.vm, .index = __yix_d1: {
        const __yix_T = if (ui.view.attrType(Detail, "index")) |__yix_A| __yix_A else @TypeOf(detailIndex(__yix_b1_0.vm.peek()));
        break :__yix_d1 try __yix_bs1_0.derive(__yix_T, .{ .vm = __yix_b1_0.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return detailIndex(__yix_ctx.vm.get());
        } }.__yix_compute);
    }, }); }) }); } }.__yix_b, struct { fn __yix_b(__yix_b1_1: anytype, __yix_bs1_1: *ui.Scope, __yix_bc1_1: *ui.Cx, __yix_bk1_1: ui.view.Sink) anyerror!void { return ui.view.emit(__yix_bs1_1, __yix_bc1_1, __yix_bk1_1, .{ ui.view.templateSite(.{ .module = "src/features/settings/view/panes/plugins.yix", .path = "PluginsPanes/keyword_if:1/branch:1", .receiver = "List", .tokens = "< List vm = { vm } / > ", .literal_text = null, .attributes = &.{ .{ .name = "vm", .tokens = "vm ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_b1_1.vm, }, __yix_builder_69: { try ui.view.previewCheckBuilder(__yix_bs1_1, List); break :__yix_builder_69 List(.{ .vm = __yix_b1_1.vm, }); }) }); } }.__yix_b)),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "PluginsPanes";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

comptime {
    _ = std;
}

const __yix_preview_source: ?[]const u8 = if (ui.view.template.preview_enabled) "\x2f\x2f\x21\x20\xe5\x8d\x8f\xe8\xae\xae\xe6\x8f\x92\xe4\xbb\xb6\xef\xbc\x88\xe7\xac\xac\x20\x35\x20\xe7\xb1\xbb\xef\xbc\x89\xe9\x9d\xa2\xe6\x9d\xbf\xe6\xad\xa3\xe6\x96\x87\xef\xbc\x88\x46\x2d\x73\x65\x74\x2d\x70\x6c\x75\x67\x69\x6e\x73\xef\xbc\x8c\xe4\xba\xba\xe5\xb7\xa5\xe9\xaa\x8c\xe6\x94\xb6\xe5\x8f\x8d\xe9\xa6\x88\xe7\xac\xac\x20\x31\x30\x20\xe6\x9d\xa1\xef\xbc\x89\xef\xbc\x9a\xe4\xb8\xa4\xe7\xba\xa7\xe5\xaf\xbc\xe8\x88\xaa\xe3\x80\x82\x0a\x2f\x2f\x21\x0a\x2f\x2f\x21\x20\x2d\x20\xe5\x88\x97\xe8\xa1\xa8\xe9\xa1\xb5\xef\xbc\x88\x50\x65\x6e\x63\x69\x6c\x20\x60\x54\x35\x6b\x39\x36\x60\xef\xbc\x8c\x60\x4c\x6f\x63\x61\x74\x69\x6f\x6e\x7b\x20\x2e\x70\x61\x67\x65\x20\x3d\x20\x35\x20\x7d\x60\xef\xbc\x89\xef\xbc\x9a\xe6\x8c\x89\xe6\x9d\xa5\xe6\xba\x90\xe5\x88\x86\xe7\xbb\x84\xe7\x9a\x84\xe9\x9d\xa2\xe6\x9d\xbf\xef\xbc\x88\xe5\xb7\xb2\xe5\x86\x85\xe7\xbd\xae\x20\x2f\x20\xe9\x9a\x8f\xe5\xba\x94\xe7\x94\xa8\xe6\x8f\x90\xe4\xbe\x9b\xef\xbc\x89\xef\xbc\x8c\xe6\xaf\x8f\xe4\xb8\xaa\xe6\x8f\x92\xe4\xbb\xb6\xe4\xb8\x80\xe8\xa1\x8c\x0a\x2f\x2f\x21\x20\x20\x20\xef\xbc\x88\x60\x52\x2e\x44\x72\x69\x6c\x6c\x52\x6f\x77\x60\xef\xbc\x9a\xe5\x9b\xbe\xe6\xa0\x87\xe3\x80\x81\xe5\x90\x8d\xe7\xa7\xb0\xe3\x80\x81\xe6\xb8\x85\xe5\x8d\x95\xe8\xaf\xb4\xe6\x98\x8e\xe3\x80\x81\xe7\x89\x88\xe6\x9c\xac\xe3\x80\x81\xe7\xae\xad\xe5\xa4\xb4\xef\xbc\x89\xef\xbc\x8c\xe7\x82\xb9\xe4\xb8\x80\xe8\xa1\x8c\xe8\xbf\x9b\xe5\x85\xa5\xe8\xaf\xa5\xe6\x8f\x92\xe4\xbb\xb6\xe7\x9a\x84\xe8\xaf\xa6\xe6\x83\x85\xe9\xa1\xb5\xef\xbc\x9b\xe6\x9c\x80\xe5\x90\x8e\xe6\x98\xaf\xe2\x80\x9c\xe8\xae\xa1\xe5\x88\x92\xe4\xb8\xad\xe2\x80\x9d\xe9\x9d\xa2\xe6\x9d\xbf\xef\xbc\x8c\xe5\x8f\xaa\xe5\x88\x97\xe8\xb7\xaf\xe7\xba\xbf\xe6\x9d\xa1\xe7\x9b\xae\x0a\x2f\x2f\x21\x20\x20\x20\xef\xbc\x88\x60\x68\x6f\x73\x74\x2f\x70\x6c\x75\x67\x69\x6e\x5f\x72\x6f\x61\x64\x6d\x61\x70\x2e\x7a\x69\x67\x60\xef\xbc\x9a\xe5\x90\x8d\xe7\xa7\xb0\x20\x2b\x20\xe2\x80\x9c\x7b\xe7\x9b\xae\xe6\xa0\x87\xe7\x89\x88\xe6\x9c\xac\x7d\x20\xe7\x89\x88\xe6\x9c\xac\xe5\xbe\x85\xe5\xae\x9e\xe6\x96\xbd\xe2\x80\x9d\xef\xbc\x8c\xe4\xb8\x8d\xe5\x8f\xaf\xe7\x82\xb9\xe5\x87\xbb\xef\xbc\x8c\xe6\xb2\xa1\xe6\x9c\x89\xe8\x83\xbd\xe5\x8a\x9b\xe6\x95\xb0\xe3\x80\x81\xe7\x89\x88\xe6\x9c\xac\xe4\xb8\x8e\xe7\xae\xad\xe5\xa4\xb4\xef\xbc\x89\xe3\x80\x82\x0a\x2f\x2f\x21\x20\x2d\x20\xe8\xaf\xa6\xe6\x83\x85\xe9\xa1\xb5\xef\xbc\x88\x60\x4b\x55\x4b\x51\x35\x60\xef\xbc\x8c\x60\x4c\x6f\x63\x61\x74\x69\x6f\x6e\x7b\x20\x2e\x70\x61\x67\x65\x20\x3d\x20\x35\x2c\x20\x2e\x73\x75\x62\x20\x3d\x20\x3c\xe6\xb3\xa8\xe5\x86\x8c\xe8\xa1\xa8\xe4\xb8\x8b\xe6\xa0\x87\x3e\x20\x7d\x60\xef\xbc\x89\xef\xbc\x9a\xe5\xa4\xb4\xe9\x83\xa8\xe5\x8d\xa1\xe7\x89\x87\xef\xbc\x88\xe5\x9b\xbe\xe6\xa0\x87\xe3\x80\x81\xe5\x90\x8d\xe7\xa7\xb0\xe3\x80\x81\xe8\xaf\xb4\xe6\x98\x8e\xe3\x80\x81\xe6\x9d\xa5\xe6\xba\x90\xe6\xa0\x87\xe7\xad\xbe\x20\x60\x57\x2e\x54\x61\x67\x60\xef\xbc\x89\xe4\xb8\x8e\x0a\x2f\x2f\x21\x20\x20\x20\xe7\xae\xa1\xe7\x90\x86\xe8\xaf\xb4\xe6\x98\x8e\xef\xbc\x9b\xe2\x80\x9c\xe6\x8f\x92\xe4\xbb\xb6\xe4\xbf\xa1\xe6\x81\xaf\xe2\x80\x9d\xef\xbc\x88\xe7\x89\x88\xe6\x9c\xac\xe3\x80\x81\xe6\x9d\x83\xe9\x99\x90\xef\xbc\x9a\xe5\x80\xbc\x20\x2b\x20\xe5\x8e\x9f\xe7\x94\x9f\xe2\x80\x9c\x3f\xe2\x80\x9d\xe6\x8f\x90\xe7\xa4\xba\xe5\x85\xa8\xe6\x96\x87\xef\xbc\x89\xef\xbc\x9b\xe6\x8f\x92\xe4\xbb\xb6\xe8\x87\xaa\xe5\xb8\xa6\xe7\x9a\x84\xe5\x81\x8f\xe5\xa5\xbd\xe5\xad\x97\xe6\xae\xb5\xef\xbc\x88\xe5\x8e\x9f\xe7\x94\x9f\xe5\xbc\x80\xe5\x85\xb3\x20\x2f\x20\xe8\xbe\x93\xe5\x85\xa5\xe6\xa1\x86\x20\x2f\x20\xe9\x80\x89\xe6\x8b\xa9\xe6\xa1\x86\xef\xbc\x8c\x0a\x2f\x2f\x21\x20\x20\x20\xe7\x94\x9f\xe6\x95\x88\xe6\x97\xb6\xe6\x9c\xba\xe6\x98\xaf\xe5\x8e\x9f\xe7\x94\x9f\xe2\x80\x9c\x3f\xe2\x80\x9d\xe5\xbc\x8f\xe6\x8f\x90\xe7\xa4\xba\xe6\x8c\x89\xe9\x92\xae\xef\xbc\x89\xe3\x80\x82\xe9\xa1\xb5\xe5\xa4\xb4\xe5\x90\x8e\xe9\x80\x80\x20\x2f\x20\xe5\x89\x8d\xe8\xbf\x9b\xe3\x80\x81\xe6\x90\x9c\xe7\xb4\xa2\xe3\x80\x81\xe6\xbb\x9a\xe5\x8a\xa8\xe4\xbd\x8d\xe7\xbd\xae\xe8\xb5\xb0\xe8\xae\xbe\xe7\xbd\xae\xe7\xaa\x97\xe5\x8f\xa3\xe7\x9a\x84\xe4\xb8\xa4\xe7\xba\xa7\xe5\xaf\xbc\xe8\x88\xaa\xe6\x9c\xba\xe5\x88\xb6\xe3\x80\x82\x0a\x2f\x2f\x21\x0a\x2f\x2f\x21\x20\x2d\x20\xe7\x8a\xb6\xe6\x80\x81\xef\xbc\x88\x51\x35\xef\xbc\x8c\x50\x65\x6e\x63\x69\x6c\x20\x58\x71\x71\x4c\x56\x20\xe7\xa8\xbf\x20\x32\xef\xbc\x89\xef\xbc\x9a\xe5\x8f\xaa\xe6\x9c\x89\xe9\x9a\x8f\xe5\xba\x94\xe7\x94\xa8\xe6\x8f\x90\xe4\xbe\x9b\xe7\x9a\x84\xe6\x8f\x92\xe4\xbb\xb6\xe6\x9c\x89\xe3\x80\x82\xe5\xbc\x80\xe5\x85\xb3\xe6\x98\xaf\xe5\x8e\x9f\xe7\x94\x9f\x20\x60\x57\x2e\x53\x77\x69\x74\x63\x68\x60\xef\xbc\x8c\xe5\xbe\x85\xe9\x87\x8d\xe5\x90\xaf\x20\x2f\x20\xe5\xb7\xb2\xe7\xa6\x81\xe7\x94\xa8\xe6\x8f\x90\xe7\xa4\xba\xe6\x98\xaf\xe5\x8e\x9f\xe7\x94\x9f\x20\x60\x57\x2e\x41\x6c\x65\x72\x74\x60\x0a\x2f\x2f\x21\x20\x20\x20\xef\xbc\x88\xe2\x80\x9c\xe7\xab\x8b\xe5\x8d\xb3\xe9\x87\x8d\xe5\x90\xaf\xe2\x80\x9d\xe6\x98\xaf\x20\x41\x6c\x65\x72\x74\x20\xe7\x9a\x84\xe5\x8e\x9f\xe7\x94\x9f\xe5\x8a\xa8\xe4\xbd\x9c\xe8\xa1\x8c\xef\xbc\x89\xef\xbc\x8c\xe7\x8a\xb6\xe6\x80\x81\xe6\xa0\x87\xe7\xad\xbe\xe6\x98\xaf\xe5\x8e\x9f\xe7\x94\x9f\x20\x60\x57\x2e\x54\x61\x67\x60\xe3\x80\x82\x0a\x2f\x2f\x21\x0a\x2f\x2f\x21\x20\xe6\x8f\x92\xe4\xbb\xb6\xe6\x98\xaf\xe8\xbf\x90\xe8\xa1\x8c\xe6\x97\xb6\xe6\x95\xb0\xe6\x8d\xae\xef\xbc\x9a\xe8\xa1\x8c\xe3\x80\x81\xe6\x96\x87\xe6\xa1\x88\xe3\x80\x81\x74\x65\x73\x74\x5f\x69\x64\x20\xe9\x83\xbd\xe7\x94\xb1\x20\x76\x69\x65\x77\x2d\x6d\x6f\x64\x65\x6c\x20\xe4\xbb\x8e\xe6\xb3\xa8\xe5\x86\x8c\xe8\xa1\xa8\xe6\xb4\xbe\xe7\x94\x9f\xef\xbc\x88\x60\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x5f\x70\x61\x6e\x65\x60\xe3\x80\x81\x60\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x2a\x60\xef\xbc\x89\xef\xbc\x8c\xe6\x9c\xac\xe6\x96\x87\xe4\xbb\xb6\xe5\x8f\xaa\xe6\x91\x86\xe7\xbb\x93\xe6\x9e\x84\xe3\x80\x82\x0a\x2f\x2f\x21\x20\xe5\x8f\xaa\xe5\xb1\x95\xe7\xa4\xba\xe6\xb3\xa8\xe5\x86\x8c\xe7\x9a\x84\xe5\x85\x83\xe6\x95\xb0\xe6\x8d\xae\xef\xbc\x8c\xe4\xb8\x8d\xe4\xb8\xba\xe6\x8f\x92\xe4\xbb\xb6\xe7\xbc\x96\xe9\x80\xa0\xe8\x83\xbd\xe5\x8a\x9b\xef\xbc\x9b\xe2\x80\x9c\xe8\xae\xa1\xe5\x88\x92\xe4\xb8\xad\xe2\x80\x9d\xe5\x8f\xaa\xe6\x9d\xa5\xe8\x87\xaa\xe6\x9c\x89\xe8\xae\xbe\xe8\xae\xa1\xe6\x96\x87\xe6\xa1\xa3\xe7\x9a\x84\xe8\xb7\xaf\xe7\xba\xbf\xe6\x9d\xa1\xe7\x9b\xae\xe3\x80\x82\x0a\x63\x6f\x6e\x73\x74\x20\x73\x74\x64\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x73\x74\x64\x22\x29\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x75\x69\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x75\x69\x22\x29\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x57\x20\x3d\x20\x75\x69\x2e\x77\x69\x64\x67\x65\x74\x73\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x6d\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x2e\x2e\x2f\x2e\x2e\x2f\x6d\x6f\x64\x65\x6c\x2f\x76\x69\x65\x77\x5f\x6d\x6f\x64\x65\x6c\x2e\x7a\x69\x67\x22\x29\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x52\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x2e\x2e\x2f\x63\x6f\x6d\x70\x6f\x6e\x65\x6e\x74\x73\x2f\x72\x6f\x77\x73\x2e\x79\x69\x78\x22\x29\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x53\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x2e\x2e\x2f\x73\x74\x79\x6c\x65\x73\x2e\x79\x73\x73\x22\x29\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x50\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x70\x6c\x75\x67\x69\x6e\x73\x2e\x79\x73\x73\x22\x29\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x44\x20\x3d\x20\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x5f\x70\x61\x6e\x65\x3b\x0a\x0a\x66\x6e\x20\x73\x65\x6e\x64\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x69\x6e\x74\x65\x6e\x74\x3a\x20\x6d\x2e\x49\x6e\x74\x65\x6e\x74\x29\x20\x76\x6f\x69\x64\x20\x7b\x0a\x20\x20\x20\x20\x76\x6d\x2e\x64\x69\x73\x70\x61\x74\x63\x68\x28\x69\x6e\x74\x65\x6e\x74\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x70\x6f\x70\x75\x70\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x69\x64\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x29\x20\x62\x6f\x6f\x6c\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x70\x6f\x70\x75\x70\x4f\x70\x65\x6e\x28\x69\x64\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x73\x65\x74\x50\x6f\x70\x75\x70\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x69\x64\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x2c\x20\x6f\x70\x65\x6e\x3a\x20\x62\x6f\x6f\x6c\x29\x20\x76\x6f\x69\x64\x20\x7b\x0a\x20\x20\x20\x20\x76\x6d\x2e\x64\x69\x73\x70\x61\x74\x63\x68\x28\x6d\x2e\x49\x6e\x74\x65\x6e\x74\x2e\x70\x6f\x70\x75\x70\x43\x68\x61\x6e\x67\x65\x64\x28\x69\x64\x2c\x20\x6f\x70\x65\x6e\x29\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x20\xe2\x94\x80\xe2\x94\x80\x20\xe5\x88\x97\xe8\xa1\xa8\xe9\xa1\xb5\x20\xe2\x94\x80\xe2\x94\x80\x0a\x0a\x66\x6e\x20\x67\x72\x6f\x75\x70\x49\x64\x28\x67\x72\x6f\x75\x70\x3a\x20\x6d\x2e\x50\x6c\x75\x67\x69\x6e\x47\x72\x6f\x75\x70\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x44\x2e\x67\x72\x6f\x75\x70\x49\x64\x28\x67\x72\x6f\x75\x70\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x67\x72\x6f\x75\x70\x48\x65\x61\x64\x65\x72\x49\x64\x28\x67\x72\x6f\x75\x70\x3a\x20\x6d\x2e\x50\x6c\x75\x67\x69\x6e\x47\x72\x6f\x75\x70\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x44\x2e\x67\x72\x6f\x75\x70\x48\x65\x61\x64\x65\x72\x49\x64\x28\x67\x72\x6f\x75\x70\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x67\x72\x6f\x75\x70\x4d\x65\x74\x61\x49\x64\x28\x67\x72\x6f\x75\x70\x3a\x20\x6d\x2e\x50\x6c\x75\x67\x69\x6e\x47\x72\x6f\x75\x70\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x44\x2e\x67\x72\x6f\x75\x70\x4d\x65\x74\x61\x49\x64\x28\x67\x72\x6f\x75\x70\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x67\x72\x6f\x75\x70\x54\x69\x74\x6c\x65\x28\x67\x72\x6f\x75\x70\x3a\x20\x6d\x2e\x50\x6c\x75\x67\x69\x6e\x47\x72\x6f\x75\x70\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x44\x2e\x67\x72\x6f\x75\x70\x54\x69\x74\x6c\x65\x28\x67\x72\x6f\x75\x70\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x67\x72\x6f\x75\x70\x53\x68\x6f\x77\x6e\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x67\x72\x6f\x75\x70\x3a\x20\x6d\x2e\x50\x6c\x75\x67\x69\x6e\x47\x72\x6f\x75\x70\x29\x20\x62\x6f\x6f\x6c\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x47\x72\x6f\x75\x70\x53\x68\x6f\x77\x6e\x28\x67\x72\x6f\x75\x70\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x69\x74\x65\x6d\x73\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x67\x72\x6f\x75\x70\x3a\x20\x6d\x2e\x50\x6c\x75\x67\x69\x6e\x47\x72\x6f\x75\x70\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x6d\x2e\x44\x72\x69\x6c\x6c\x49\x74\x65\x6d\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x49\x74\x65\x6d\x73\x28\x67\x72\x6f\x75\x70\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x6c\x69\x73\x74\x45\x6d\x70\x74\x79\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x29\x20\x62\x6f\x6f\x6c\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x4c\x69\x73\x74\x45\x6d\x70\x74\x79\x28\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\xe4\xb8\x80\xe4\xb8\xaa\xe6\x9d\xa5\xe6\xba\x90\xe5\x88\x86\xe7\xbb\x84\xef\xbc\x88\x60\x52\x76\x42\x37\x37\x60\x20\x2f\x20\x60\x68\x68\x63\x38\x73\x60\xef\xbc\x89\xef\xbc\x9a\x50\x61\x6e\x65\x20\x48\x65\x61\x64\x65\x72\xef\xbc\x88\xe6\xa0\x87\xe9\xa2\x98\x20\x2b\x20\xe2\x80\x9c\x33\x20\xe4\xb8\xaa\xe5\x8d\x8f\xe8\xae\xae\x20\xc2\xb7\x20\xe9\x9a\x8f\xe5\xba\x94\xe7\x94\xa8\xe7\xae\xa1\xe7\x90\x86\xe2\x80\x9d\xef\xbc\x89\x2b\x20\xe8\xa1\x8c\xe5\x8d\xa1\xe7\x89\x87\xe3\x80\x82\x0a\x66\x6e\x20\x47\x72\x6f\x75\x70\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x67\x72\x6f\x75\x70\x3a\x20\x6d\x2e\x50\x6c\x75\x67\x69\x6e\x47\x72\x6f\x75\x70\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x67\x72\x6f\x75\x70\x49\x64\x28\x67\x72\x6f\x75\x70\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x70\x61\x6e\x65\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x67\x72\x6f\x75\x70\x53\x68\x6f\x77\x6e\x28\x76\x6d\x2c\x20\x67\x72\x6f\x75\x70\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x67\x72\x6f\x75\x70\x48\x65\x61\x64\x65\x72\x49\x64\x28\x67\x72\x6f\x75\x70\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x70\x61\x6e\x65\x5f\x68\x65\x61\x64\x65\x72\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x70\x61\x6e\x65\x5f\x74\x69\x74\x6c\x65\x7d\x3e\x7b\x67\x72\x6f\x75\x70\x54\x69\x74\x6c\x65\x28\x67\x72\x6f\x75\x70\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x73\x70\x61\x63\x65\x72\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x67\x72\x6f\x75\x70\x4d\x65\x74\x61\x49\x64\x28\x67\x72\x6f\x75\x70\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x70\x61\x6e\x65\x5f\x6d\x65\x74\x61\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x70\x61\x6e\x65\x5f\x6d\x65\x74\x61\x5f\x62\x6f\x78\x7d\x3e\x7b\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x47\x72\x6f\x75\x70\x4d\x65\x74\x61\x28\x67\x72\x6f\x75\x70\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x70\x61\x6e\x65\x5f\x62\x6f\x64\x79\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x7b\x66\x6f\x72\x20\x28\x69\x74\x65\x6d\x73\x28\x76\x6d\x2c\x20\x67\x72\x6f\x75\x70\x29\x29\x20\x7c\x69\x74\x65\x6d\x7c\x20\x3c\x52\x2e\x44\x72\x69\x6c\x6c\x52\x6f\x77\x20\x6b\x65\x79\x3d\x7b\x69\x74\x65\x6d\x2e\x6b\x65\x79\x7d\x20\x76\x6d\x3d\x7b\x76\x6d\x7d\x20\x69\x74\x65\x6d\x3d\x7b\x69\x74\x65\x6d\x7d\x20\x2f\x3e\x7d\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x66\x6e\x20\x70\x6c\x61\x6e\x6e\x65\x64\x53\x68\x6f\x77\x6e\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x29\x20\x62\x6f\x6f\x6c\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x50\x6c\x61\x6e\x6e\x65\x64\x53\x68\x6f\x77\x6e\x28\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x70\x6c\x61\x6e\x6e\x65\x64\x49\x74\x65\x6d\x73\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x6d\x2e\x50\x6c\x61\x6e\x6e\x65\x64\x49\x74\x65\x6d\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x50\x6c\x61\x6e\x6e\x65\x64\x49\x74\x65\x6d\x73\x28\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x70\x6c\x61\x6e\x6e\x65\x64\x49\x63\x6f\x6e\x28\x69\x74\x65\x6d\x3a\x20\x6d\x2e\x50\x6c\x61\x6e\x6e\x65\x64\x49\x74\x65\x6d\x29\x20\x75\x69\x2e\x53\x76\x67\x41\x73\x73\x65\x74\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x75\x69\x2e\x69\x63\x6f\x6e\x73\x2e\x67\x65\x74\x28\x69\x74\x65\x6d\x2e\x69\x63\x6f\x6e\x29\x20\x6f\x72\x65\x6c\x73\x65\x20\x75\x69\x2e\x69\x63\x6f\x6e\x73\x2e\x70\x6c\x75\x67\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\xe8\xae\xa1\xe5\x88\x92\xe8\xa1\x8c\xef\xbc\x88\x60\x57\x6c\x6d\x78\x65\x60\xef\xbc\x89\xef\xbc\x9a\xe5\x9b\xbe\xe6\xa0\x87\xe5\xba\x95\x20\x2b\x20\xe5\x90\x8d\xe7\xa7\xb0\x20\x2f\x20\xe2\x80\x9c\x30\x2e\x35\x20\xe7\x89\x88\xe6\x9c\xac\xe5\xbe\x85\xe5\xae\x9e\xe6\x96\xbd\xe2\x80\x9d\xef\xbc\x8c\xe8\xa1\x8c\xe9\x97\xb4\xe5\x8f\x91\xe4\xb8\x9d\xe7\xba\xbf\xe5\x90\x8c\x20\x60\x44\x72\x69\x6c\x6c\x52\x6f\x77\x60\xef\xbc\x9b\xe4\xb8\x8d\xe5\x8f\xaf\xe7\x82\xb9\xe5\x87\xbb\xe3\x80\x82\x0a\x66\x6e\x20\x50\x6c\x61\x6e\x6e\x65\x64\x52\x6f\x77\x28\x69\x74\x65\x6d\x3a\x20\x6d\x2e\x50\x6c\x61\x6e\x6e\x65\x64\x49\x74\x65\x6d\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x69\x74\x65\x6d\x2e\x72\x6f\x77\x5f\x69\x64\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x50\x2e\x70\x6c\x61\x6e\x6e\x65\x64\x5f\x72\x6f\x77\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6f\x76\x65\x72\x76\x69\x65\x77\x5f\x74\x69\x6c\x65\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x69\x63\x6f\x6e\x20\x73\x72\x63\x3d\x7b\x70\x6c\x61\x6e\x6e\x65\x64\x49\x63\x6f\x6e\x28\x69\x74\x65\x6d\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x50\x2e\x70\x6c\x61\x6e\x6e\x65\x64\x5f\x69\x63\x6f\x6e\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x44\x72\x69\x6c\x6c\x49\x6e\x6e\x65\x72\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x6c\x61\x73\x74\x20\x3d\x20\x69\x74\x65\x6d\x2e\x6c\x61\x73\x74\x20\x7d\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x64\x72\x69\x6c\x6c\x5f\x63\x6f\x70\x79\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x69\x74\x65\x6d\x2e\x74\x69\x74\x6c\x65\x5f\x69\x64\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x50\x2e\x70\x6c\x61\x6e\x6e\x65\x64\x5f\x74\x69\x74\x6c\x65\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x64\x72\x69\x6c\x6c\x5f\x74\x65\x78\x74\x5f\x62\x6f\x78\x7d\x3e\x7b\x69\x74\x65\x6d\x2e\x74\x69\x74\x6c\x65\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x69\x74\x65\x6d\x2e\x73\x75\x6d\x6d\x61\x72\x79\x5f\x69\x64\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x64\x72\x69\x6c\x6c\x5f\x73\x75\x6d\x6d\x61\x72\x79\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x64\x72\x69\x6c\x6c\x5f\x74\x65\x78\x74\x5f\x62\x6f\x78\x7d\x3e\x7b\x69\x74\x65\x6d\x2e\x73\x75\x6d\x6d\x61\x72\x79\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\xe2\x80\x9c\xe8\xae\xa1\xe5\x88\x92\xe4\xb8\xad\xe2\x80\x9d\xef\xbc\x88\x60\x67\x33\x62\x78\x4f\x33\x60\xef\xbc\x89\xef\xbc\x9a\xe9\xa1\xb5\xe5\xa4\xb4\xe5\x8f\xaa\xe6\x9c\x89\xe6\xa0\x87\xe9\xa2\x98\xef\xbc\x8c\xe6\xb2\xa1\xe6\x9c\x89\xe8\xae\xa1\xe6\x95\xb0\xe3\x80\x82\x0a\x66\x6e\x20\x50\x6c\x61\x6e\x6e\x65\x64\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x65\x74\x74\x69\x6e\x67\x73\x2e\x70\x6c\x75\x67\x69\x6e\x73\x2e\x70\x6c\x61\x6e\x6e\x65\x64\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x70\x61\x6e\x65\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x70\x6c\x61\x6e\x6e\x65\x64\x53\x68\x6f\x77\x6e\x28\x76\x6d\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x65\x74\x74\x69\x6e\x67\x73\x2e\x70\x6c\x75\x67\x69\x6e\x73\x2e\x70\x6c\x61\x6e\x6e\x65\x64\x2e\x68\x65\x61\x64\x65\x72\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x70\x61\x6e\x65\x5f\x68\x65\x61\x64\x65\x72\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x70\x61\x6e\x65\x5f\x74\x69\x74\x6c\x65\x7d\x3e\x7b\x44\x2e\x70\x6c\x61\x6e\x6e\x65\x64\x5f\x74\x69\x74\x6c\x65\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x70\x61\x6e\x65\x5f\x62\x6f\x64\x79\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x7b\x66\x6f\x72\x20\x28\x70\x6c\x61\x6e\x6e\x65\x64\x49\x74\x65\x6d\x73\x28\x76\x6d\x29\x29\x20\x7c\x69\x74\x65\x6d\x7c\x20\x3c\x50\x6c\x61\x6e\x6e\x65\x64\x52\x6f\x77\x20\x6b\x65\x79\x3d\x7b\x69\x74\x65\x6d\x2e\x6b\x65\x79\x7d\x20\x69\x74\x65\x6d\x3d\x7b\x69\x74\x65\x6d\x7d\x20\x2f\x3e\x7d\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x66\x6e\x20\x4c\x69\x73\x74\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x65\x74\x74\x69\x6e\x67\x73\x2e\x70\x6c\x75\x67\x69\x6e\x73\x2e\x67\x72\x6f\x75\x70\x73\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x50\x2e\x70\x61\x6e\x65\x73\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x47\x72\x6f\x75\x70\x20\x76\x6d\x3d\x7b\x76\x6d\x7d\x20\x67\x72\x6f\x75\x70\x3d\x7b\x2e\x62\x75\x69\x6c\x74\x69\x6e\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x47\x72\x6f\x75\x70\x20\x76\x6d\x3d\x7b\x76\x6d\x7d\x20\x67\x72\x6f\x75\x70\x3d\x7b\x2e\x62\x75\x6e\x64\x6c\x65\x64\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x65\x74\x74\x69\x6e\x67\x73\x2e\x70\x6c\x75\x67\x69\x6e\x73\x2e\x65\x6d\x70\x74\x79\x22\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x6c\x69\x73\x74\x45\x6d\x70\x74\x79\x28\x76\x6d\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x45\x6d\x70\x74\x79\x20\x69\x63\x6f\x6e\x3d\x7b\x75\x69\x2e\x69\x63\x6f\x6e\x73\x2e\x67\x65\x74\x28\x22\x70\x75\x7a\x7a\x6c\x65\x22\x29\x2e\x3f\x7d\x20\x74\x69\x74\x6c\x65\x3d\x22\xe6\xb2\xa1\xe6\x9c\x89\xe5\xb7\xb2\xe6\xb3\xa8\xe5\x86\x8c\xe7\x9a\x84\xe6\x8f\x92\xe4\xbb\xb6\x22\x20\x64\x65\x73\x63\x72\x69\x70\x74\x69\x6f\x6e\x3d\x22\xe5\xb7\xb2\xe5\x86\x85\xe7\xbd\xae\xe4\xb8\x8e\xe9\x9a\x8f\xe5\xba\x94\xe7\x94\xa8\xe6\x8f\x90\xe4\xbe\x9b\xe7\x9a\x84\xe6\x8f\x92\xe4\xbb\xb6\xe4\xbc\x9a\xe5\x88\x97\xe5\x9c\xa8\xe8\xbf\x99\xe9\x87\x8c\xe3\x80\x82\x22\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x50\x6c\x61\x6e\x6e\x65\x64\x20\x76\x6d\x3d\x7b\x76\x6d\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x20\xe2\x94\x80\xe2\x94\x80\x20\xe8\xaf\xa6\xe6\x83\x85\xe9\xa1\xb5\x20\xe2\x94\x80\xe2\x94\x80\x0a\x0a\x66\x6e\x20\x64\x65\x74\x61\x69\x6c\x49\x6e\x64\x65\x78\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x29\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x44\x65\x74\x61\x69\x6c\x28\x29\x20\x6f\x72\x65\x6c\x73\x65\x20\x30\x3b\x0a\x7d\x0a\x66\x6e\x20\x64\x65\x74\x61\x69\x6c\x53\x68\x6f\x77\x6e\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x29\x20\x62\x6f\x6f\x6c\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x44\x65\x74\x61\x69\x6c\x53\x68\x6f\x77\x6e\x28\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x70\x69\x64\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x69\x6e\x64\x65\x78\x3a\x20\x75\x38\x2c\x20\x70\x61\x72\x74\x3a\x20\x6d\x2e\x50\x6c\x75\x67\x69\x6e\x50\x61\x72\x74\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x49\x64\x28\x69\x6e\x64\x65\x78\x2c\x20\x70\x61\x72\x74\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x69\x63\x6f\x6e\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x69\x6e\x64\x65\x78\x3a\x20\x75\x38\x29\x20\x75\x69\x2e\x53\x76\x67\x41\x73\x73\x65\x74\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x75\x69\x2e\x69\x63\x6f\x6e\x73\x2e\x67\x65\x74\x28\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x49\x63\x6f\x6e\x28\x69\x6e\x64\x65\x78\x29\x29\x20\x6f\x72\x65\x6c\x73\x65\x20\x75\x69\x2e\x69\x63\x6f\x6e\x73\x2e\x70\x6c\x75\x67\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\xe6\xa6\x82\xe8\xa6\x81\xef\xbc\x88\x60\x42\x35\x37\x76\x62\x60\xef\xbc\x89\xef\xbc\x9a\xe5\xa4\xb4\xe9\x83\xa8\xe5\x8d\xa1\xe7\x89\x87\x20\x2b\x20\xe7\xae\xa1\xe7\x90\x86\xe8\xaf\xb4\xe6\x98\x8e\xe3\x80\x82\x0a\x66\x6e\x20\x53\x75\x6d\x6d\x61\x72\x79\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x69\x6e\x64\x65\x78\x3a\x20\x75\x38\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x50\x2e\x73\x75\x6d\x6d\x61\x72\x79\x5f\x70\x61\x6e\x65\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x70\x69\x64\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x2c\x20\x2e\x68\x65\x61\x64\x65\x72\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x50\x2e\x68\x65\x61\x64\x5f\x63\x61\x72\x64\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x50\x2e\x68\x65\x61\x64\x5f\x74\x69\x6c\x65\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x69\x63\x6f\x6e\x20\x73\x72\x63\x3d\x7b\x69\x63\x6f\x6e\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x50\x2e\x68\x65\x61\x64\x5f\x69\x63\x6f\x6e\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x50\x2e\x68\x65\x61\x64\x5f\x63\x6f\x70\x79\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x50\x2e\x68\x65\x61\x64\x5f\x6e\x61\x6d\x65\x7d\x20\x62\x6f\x78\x3d\x7b\x50\x2e\x68\x65\x61\x64\x5f\x74\x65\x78\x74\x5f\x62\x6f\x78\x7d\x3e\x7b\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x4e\x61\x6d\x65\x28\x69\x6e\x64\x65\x78\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x70\x69\x64\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x2c\x20\x2e\x73\x75\x6d\x6d\x61\x72\x79\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x50\x2e\x68\x65\x61\x64\x5f\x73\x75\x6d\x6d\x61\x72\x79\x7d\x20\x62\x6f\x78\x3d\x7b\x50\x2e\x68\x65\x61\x64\x5f\x74\x65\x78\x74\x5f\x62\x6f\x78\x7d\x3e\x7b\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x44\x65\x73\x63\x72\x69\x70\x74\x69\x6f\x6e\x28\x69\x6e\x64\x65\x78\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x7b\x69\x66\x20\x28\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x53\x74\x61\x74\x65\x54\x61\x67\x53\x68\x6f\x77\x6e\x28\x69\x6e\x64\x65\x78\x29\x29\x20\x3c\x57\x2e\x54\x61\x67\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x70\x69\x64\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x2c\x20\x2e\x73\x74\x61\x74\x65\x29\x7d\x20\x6c\x61\x62\x65\x6c\x3d\x7b\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x53\x74\x61\x74\x65\x54\x61\x67\x28\x69\x6e\x64\x65\x78\x29\x7d\x20\x63\x6f\x6c\x6f\x72\x3d\x7b\x73\x74\x61\x74\x65\x43\x6f\x6c\x6f\x72\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x29\x7d\x20\x73\x69\x7a\x65\x3d\x7b\x2e\x73\x6d\x7d\x20\x2f\x3e\x7d\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x54\x61\x67\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x70\x69\x64\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x2c\x20\x2e\x6f\x72\x69\x67\x69\x6e\x29\x7d\x20\x6c\x61\x62\x65\x6c\x3d\x7b\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x4f\x72\x69\x67\x69\x6e\x54\x61\x67\x28\x69\x6e\x64\x65\x78\x29\x7d\x20\x73\x69\x7a\x65\x3d\x7b\x2e\x73\x6d\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x50\x2e\x6e\x6f\x74\x65\x5f\x77\x72\x61\x70\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x70\x69\x64\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x2c\x20\x2e\x76\x65\x72\x73\x69\x6f\x6e\x5f\x6d\x65\x73\x73\x61\x67\x65\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x50\x2e\x6e\x6f\x74\x65\x7d\x20\x62\x6f\x78\x3d\x7b\x50\x2e\x6e\x6f\x74\x65\x5f\x62\x6f\x78\x7d\x3e\x7b\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x4e\x6f\x74\x65\x28\x69\x6e\x64\x65\x78\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x20\xe2\x94\x80\xe2\x94\x80\x20\xe7\x8a\xb6\xe6\x80\x81\xef\xbc\x88\xe9\x9a\x8f\xe5\xba\x94\xe7\x94\xa8\xe6\x8f\x92\xe4\xbb\xb6\xe7\x9a\x84\xe5\x90\xaf\xe7\x94\xa8\xe5\xbc\x80\xe5\x85\xb3\xef\xbc\x8c\x50\x4c\x55\x47\x49\x4e\x5f\x41\x52\x43\x48\x5f\x50\x4c\x41\x4e\x20\x36\x2e\x32\x2e\x31\x20\x51\x35\xef\xbc\x9b\x50\x65\x6e\x63\x69\x6c\x20\x58\x71\x71\x4c\x56\x20\xe7\xa8\xbf\x20\x32\xef\xbc\x89\x20\xe2\x94\x80\xe2\x94\x80\x0a\x0a\x66\x6e\x20\x73\x74\x61\x74\x65\x43\x6f\x6c\x6f\x72\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x69\x6e\x64\x65\x78\x3a\x20\x75\x38\x29\x20\x57\x2e\x54\x61\x67\x43\x6f\x6c\x6f\x72\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x69\x66\x20\x28\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x50\x65\x6e\x64\x69\x6e\x67\x28\x69\x6e\x64\x65\x78\x29\x29\x20\x2e\x77\x61\x72\x6e\x69\x6e\x67\x20\x65\x6c\x73\x65\x20\x2e\x6e\x65\x75\x74\x72\x61\x6c\x3b\x0a\x7d\x0a\x66\x6e\x20\x74\x6f\x67\x67\x6c\x65\x53\x68\x6f\x77\x6e\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x69\x6e\x64\x65\x78\x3a\x20\x75\x38\x29\x20\x62\x6f\x6f\x6c\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x54\x6f\x67\x67\x6c\x65\x53\x68\x6f\x77\x6e\x28\x69\x6e\x64\x65\x78\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x73\x65\x74\x45\x6e\x61\x62\x6c\x65\x64\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x69\x6e\x64\x65\x78\x3a\x20\x75\x38\x2c\x20\x76\x61\x6c\x75\x65\x3a\x20\x62\x6f\x6f\x6c\x29\x20\x76\x6f\x69\x64\x20\x7b\x0a\x20\x20\x20\x20\x76\x6d\x2e\x64\x69\x73\x70\x61\x74\x63\x68\x28\x6d\x2e\x49\x6e\x74\x65\x6e\x74\x2e\x73\x65\x74\x50\x6c\x75\x67\x69\x6e\x45\x6e\x61\x62\x6c\x65\x64\x28\x69\x6e\x64\x65\x78\x2c\x20\x76\x61\x6c\x75\x65\x29\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x72\x65\x73\x74\x61\x72\x74\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x29\x20\x76\x6f\x69\x64\x20\x7b\x0a\x20\x20\x20\x20\x76\x6d\x2e\x64\x69\x73\x70\x61\x74\x63\x68\x28\x6d\x2e\x49\x6e\x74\x65\x6e\x74\x2e\x72\x75\x6e\x43\x6f\x6d\x6d\x61\x6e\x64\x28\x2e\x72\x65\x73\x74\x61\x72\x74\x5f\x61\x70\x70\x29\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x65\x6e\x61\x62\x6c\x65\x64\x41\x31\x31\x79\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x69\x6e\x64\x65\x78\x3a\x20\x75\x38\x29\x20\x3f\x75\x69\x2e\x41\x31\x31\x79\x50\x72\x6f\x70\x73\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x2e\x7b\x20\x2e\x72\x6f\x6c\x65\x20\x3d\x20\x2e\x73\x77\x69\x74\x63\x68\x5f\x72\x6f\x6c\x65\x2c\x20\x2e\x6c\x61\x62\x65\x6c\x20\x3d\x20\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x54\x6f\x67\x67\x6c\x65\x4c\x61\x62\x65\x6c\x28\x69\x6e\x64\x65\x78\x29\x2c\x20\x2e\x63\x68\x65\x63\x6b\x65\x64\x20\x3d\x20\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x45\x6e\x61\x62\x6c\x65\x64\x44\x72\x61\x66\x74\x28\x69\x6e\x64\x65\x78\x29\x2c\x20\x2e\x64\x69\x73\x61\x62\x6c\x65\x64\x20\x3d\x20\x76\x6d\x2e\x69\x73\x53\x61\x76\x69\x6e\x67\x28\x29\x20\x7d\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\xe2\x80\x9c\xe7\x8a\xb6\xe6\x80\x81\xe2\x80\x9d\xe5\x88\x86\xe7\xbb\x84\xef\xbc\x88\x34\x31\x20\xe5\x8f\xb7\xe8\xaf\xb4\xe6\x98\x8e\xe7\xa8\xbf\xef\xbc\x89\xef\xbc\x9a\x50\x61\x6e\x65\x20\x48\x65\x61\x64\x65\x72\xe2\x80\x9c\xe7\x8a\xb6\xe6\x80\x81\xe2\x80\x9d\x2b\x20\xe5\x8f\xb3\xe4\xbe\xa7\xe2\x80\x9c\xe9\x87\x8d\xe5\x90\xaf\xe5\x90\x8e\xe7\x94\x9f\xe6\x95\x88\xe2\x80\x9d\xef\xbc\x8c\xe4\xb8\x80\xe8\xa1\x8c\x20\x53\x65\x74\x74\x69\x6e\x67\xef\xbc\x88\xe6\xa0\x87\xe7\xad\xbe\x20\x2b\x20\xe8\xaf\xb4\xe6\x98\x8e\x20\x2b\x20\xe5\x8e\x9f\xe7\x94\x9f\x20\x60\x57\x2e\x53\x77\x69\x74\x63\x68\x60\xef\xbc\x89\xe3\x80\x82\x0a\x2f\x2f\x2f\x20\xe5\x8f\xaa\xe6\x9c\x89\xe9\x9a\x8f\xe5\xba\x94\xe7\x94\xa8\xe6\x8f\x90\xe4\xbe\x9b\xe7\x9a\x84\xe6\x8f\x92\xe4\xbb\xb6\xe6\x9c\x89\xe8\xbf\x99\xe4\xb8\x80\xe7\xbb\x84\xef\xbc\x88\x51\x35\x61\xef\xbc\x89\xe3\x80\x82\xe6\x8b\xa8\xe5\x8a\xa8\xe5\xbc\x80\xe5\x85\xb3\xe6\x98\xaf\xe2\x80\x9c\xe6\x94\xb9\xe4\xba\x86\xe6\x9c\xaa\xe4\xbf\x9d\xe5\xad\x98\xe2\x80\x9d\xef\xbc\x88\x53\x48\x31\x67\x62\xef\xbc\x8c\xe6\xb2\xbf\xe7\x94\xa8\xe4\xbf\x9d\xe5\xad\x98\xe6\xa0\x8f\xef\xbc\x89\xef\xbc\x9b\xe4\xbf\x9d\xe5\xad\x98\xe5\x90\x8e\xe4\xb8\x8e\xe6\x9c\xac\xe6\xac\xa1\xe5\x90\xaf\xe5\x8a\xa8\xe7\x9a\x84\xe7\x8a\xb6\xe6\x80\x81\xe4\xb8\x8d\xe5\x90\x8c\xe6\x97\xb6\xe6\x98\xbe\xe7\xa4\xba\x0a\x2f\x2f\x2f\x20\xe5\x8e\x9f\xe7\x94\x9f\x20\x77\x61\x72\x6e\x69\x6e\x67\x20\x60\x57\x2e\x41\x6c\x65\x72\x74\x60\x20\xe4\xb8\x8e\xe2\x80\x9c\xe7\xab\x8b\xe5\x8d\xb3\xe9\x87\x8d\xe5\x90\xaf\xe2\x80\x9d\xef\xbc\x88\x4e\x48\x72\x32\x4c\x20\x2f\x20\x44\x7a\x50\x62\x4f\xef\xbc\x89\xef\xbc\x9b\xe6\x9c\xac\xe6\xac\xa1\xe6\xb2\xa1\xe6\x9c\x89\xe5\x8a\xa0\xe8\xbd\xbd\xe6\x97\xb6\xe6\x98\xbe\xe7\xa4\xba\xe5\x8e\x9f\xe7\x94\x9f\x20\x69\x6e\x66\x6f\x20\x60\x57\x2e\x41\x6c\x65\x72\x74\x60\xef\xbc\x88\x42\x30\x51\x58\x67\x36\x20\x2f\x20\x49\x65\x43\x7a\x59\xef\xbc\x89\xe3\x80\x82\x0a\x66\x6e\x20\x53\x74\x61\x74\x75\x73\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x69\x6e\x64\x65\x78\x3a\x20\x75\x38\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x61\x31\x31\x79\x20\x3d\x20\x63\x6f\x6d\x70\x75\x74\x65\x64\x28\x65\x6e\x61\x62\x6c\x65\x64\x41\x31\x31\x79\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x29\x29\x3b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x70\x69\x64\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x2c\x20\x2e\x73\x74\x61\x74\x75\x73\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x70\x61\x6e\x65\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x74\x6f\x67\x67\x6c\x65\x53\x68\x6f\x77\x6e\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x70\x61\x6e\x65\x5f\x68\x65\x61\x64\x65\x72\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x70\x61\x6e\x65\x5f\x74\x69\x74\x6c\x65\x7d\x3e\x7b\x44\x2e\x73\x74\x61\x74\x75\x73\x5f\x74\x69\x74\x6c\x65\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x73\x70\x61\x63\x65\x72\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x70\x61\x6e\x65\x5f\x6d\x65\x74\x61\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x70\x61\x6e\x65\x5f\x6d\x65\x74\x61\x5f\x62\x6f\x78\x7d\x3e\x7b\x44\x2e\x73\x74\x61\x74\x75\x73\x5f\x6d\x65\x74\x61\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x70\x61\x6e\x65\x5f\x62\x6f\x64\x79\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x53\x65\x74\x74\x69\x6e\x67\x52\x6f\x77\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x6c\x61\x73\x74\x20\x3d\x20\x74\x72\x75\x65\x20\x7d\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x6c\x69\x6e\x65\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x63\x6f\x70\x79\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x6c\x61\x62\x65\x6c\x7d\x3e\x7b\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x54\x6f\x67\x67\x6c\x65\x4c\x61\x62\x65\x6c\x28\x69\x6e\x64\x65\x78\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x70\x69\x64\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x2c\x20\x2e\x65\x6e\x61\x62\x6c\x65\x64\x5f\x68\x69\x6e\x74\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x68\x69\x6e\x74\x7d\x20\x62\x6f\x78\x3d\x7b\x50\x2e\x74\x6f\x67\x67\x6c\x65\x5f\x68\x69\x6e\x74\x5f\x62\x6f\x78\x7d\x3e\x7b\x44\x2e\x74\x6f\x67\x67\x6c\x65\x5f\x68\x69\x6e\x74\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x53\x77\x69\x74\x63\x68\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x70\x69\x64\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x2c\x20\x2e\x65\x6e\x61\x62\x6c\x65\x64\x29\x7d\x20\x63\x68\x65\x63\x6b\x65\x64\x3d\x7b\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x45\x6e\x61\x62\x6c\x65\x64\x44\x72\x61\x66\x74\x28\x69\x6e\x64\x65\x78\x29\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x76\x6d\x2e\x69\x73\x53\x61\x76\x69\x6e\x67\x28\x29\x7d\x20\x61\x31\x31\x79\x3d\x7b\x61\x31\x31\x79\x7d\x20\x6f\x6e\x43\x68\x61\x6e\x67\x65\x3d\x7b\x7c\x76\x7c\x20\x73\x65\x74\x45\x6e\x61\x62\x6c\x65\x64\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x2c\x20\x76\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x70\x69\x64\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x2c\x20\x2e\x65\x6e\x61\x62\x6c\x65\x64\x5f\x65\x72\x72\x6f\x72\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x65\x72\x72\x6f\x72\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x45\x6e\x61\x62\x6c\x65\x49\x6e\x76\x61\x6c\x69\x64\x28\x69\x6e\x64\x65\x78\x29\x7d\x3e\x7b\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x45\x6e\x61\x62\x6c\x65\x50\x72\x6f\x62\x6c\x65\x6d\x28\x69\x6e\x64\x65\x78\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x70\x69\x64\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x2c\x20\x2e\x6e\x6f\x74\x69\x63\x65\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x50\x2e\x6e\x6f\x74\x69\x63\x65\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x50\x65\x6e\x64\x69\x6e\x67\x28\x69\x6e\x64\x65\x78\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x41\x6c\x65\x72\x74\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x77\x61\x72\x6e\x69\x6e\x67\x7d\x20\x74\x69\x74\x6c\x65\x3d\x7b\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x50\x65\x6e\x64\x69\x6e\x67\x54\x69\x74\x6c\x65\x28\x69\x6e\x64\x65\x78\x29\x7d\x20\x6d\x65\x73\x73\x61\x67\x65\x3d\x7b\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x50\x65\x6e\x64\x69\x6e\x67\x4d\x65\x73\x73\x61\x67\x65\x28\x69\x6e\x64\x65\x78\x29\x7d\x20\x61\x63\x74\x69\x6f\x6e\x4c\x61\x62\x65\x6c\x3d\x7b\x44\x2e\x72\x65\x73\x74\x61\x72\x74\x5f\x6c\x61\x62\x65\x6c\x7d\x20\x61\x63\x74\x69\x6f\x6e\x49\x63\x6f\x6e\x41\x73\x73\x65\x74\x3d\x7b\x75\x69\x2e\x69\x63\x6f\x6e\x73\x2e\x72\x6f\x74\x61\x74\x65\x5f\x63\x63\x77\x7d\x20\x61\x63\x74\x69\x6f\x6e\x54\x65\x73\x74\x49\x64\x3d\x7b\x70\x69\x64\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x2c\x20\x2e\x72\x65\x73\x74\x61\x72\x74\x29\x7d\x20\x6f\x6e\x41\x63\x74\x69\x6f\x6e\x3d\x7b\x72\x65\x73\x74\x61\x72\x74\x28\x76\x6d\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x70\x69\x64\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x2c\x20\x2e\x64\x69\x73\x61\x62\x6c\x65\x64\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x50\x2e\x6e\x6f\x74\x69\x63\x65\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x44\x69\x73\x61\x62\x6c\x65\x64\x53\x68\x6f\x77\x6e\x28\x69\x6e\x64\x65\x78\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x41\x6c\x65\x72\x74\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x69\x6e\x66\x6f\x7d\x20\x74\x69\x74\x6c\x65\x3d\x7b\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x44\x69\x73\x61\x62\x6c\x65\x64\x54\x69\x74\x6c\x65\x28\x69\x6e\x64\x65\x78\x29\x7d\x20\x6d\x65\x73\x73\x61\x67\x65\x3d\x7b\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x44\x69\x73\x61\x62\x6c\x65\x64\x4d\x65\x73\x73\x61\x67\x65\x28\x69\x6e\x64\x65\x78\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\xe6\x9d\x83\xe9\x99\x90\xe7\x9a\x84\xe2\x80\x9c\x3f\xe2\x80\x9d\xef\xbc\x9a\xe5\x8e\x9f\xe7\x94\x9f\x20\x67\x68\x6f\x73\x74\x20\xe5\x9b\xbe\xe6\xa0\x87\xe6\x8c\x89\xe9\x92\xae\x20\x2b\x20\xe5\x8e\x9f\xe7\x94\x9f\x20\x54\x6f\x6f\x6c\x74\x69\x70\xef\xbc\x88\xe4\xb8\x8a\xe6\x96\xb9\xe3\x80\x81\x34\x35\x30\x6d\x73\xef\xbc\x8c\xe6\x82\xac\xe5\x81\x9c\x20\x2f\x20\xe8\x81\x9a\xe7\x84\xa6\x20\x2f\x20\xe7\x82\xb9\xe5\x87\xbb\xe6\x89\x93\xe5\xbc\x80\xef\xbc\x9b\xe6\x95\xb4\xe7\xaa\x97\x20\x45\x73\x63\x61\x70\x65\x20\xe5\x85\x88\xe6\x94\xb6\xe8\xb5\xb7\xe5\xae\x83\xef\xbc\x89\xe3\x80\x82\x0a\x66\x6e\x20\x50\x65\x72\x6d\x69\x73\x73\x69\x6f\x6e\x54\x69\x70\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x69\x6e\x64\x65\x78\x3a\x20\x75\x38\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x74\x69\x70\x20\x3d\x20\x63\x6f\x6d\x70\x75\x74\x65\x64\x28\x70\x69\x64\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x2c\x20\x2e\x70\x65\x72\x6d\x69\x73\x73\x69\x6f\x6e\x73\x5f\x74\x69\x70\x29\x29\x3b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x62\x75\x74\x74\x6f\x6e\x20\x3d\x20\x63\x6f\x6d\x70\x75\x74\x65\x64\x28\x70\x69\x64\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x2c\x20\x2e\x70\x65\x72\x6d\x69\x73\x73\x69\x6f\x6e\x73\x29\x29\x3b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x68\x65\x6c\x70\x5f\x73\x6c\x6f\x74\x7d\x20\x6f\x6e\x46\x6f\x63\x75\x73\x3d\x7b\x73\x65\x74\x50\x6f\x70\x75\x70\x28\x76\x6d\x2c\x20\x74\x69\x70\x2c\x20\x74\x72\x75\x65\x29\x7d\x20\x6f\x6e\x42\x6c\x75\x72\x3d\x7b\x73\x65\x74\x50\x6f\x70\x75\x70\x28\x76\x6d\x2c\x20\x74\x69\x70\x2c\x20\x66\x61\x6c\x73\x65\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x20\x74\x65\x78\x74\x3d\x7b\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x50\x65\x72\x6d\x69\x73\x73\x69\x6f\x6e\x73\x28\x69\x6e\x64\x65\x78\x29\x7d\x20\x70\x6f\x73\x69\x74\x69\x6f\x6e\x3d\x7b\x2e\x74\x6f\x70\x7d\x20\x77\x69\x64\x74\x68\x3d\x7b\x32\x39\x32\x7d\x20\x6f\x70\x65\x6e\x3d\x7b\x70\x6f\x70\x75\x70\x28\x76\x6d\x2c\x20\x74\x69\x70\x29\x7d\x20\x6f\x6e\x4f\x70\x65\x6e\x43\x68\x61\x6e\x67\x65\x3d\x7b\x7c\x6f\x7c\x20\x73\x65\x74\x50\x6f\x70\x75\x70\x28\x76\x6d\x2c\x20\x74\x69\x70\x2c\x20\x6f\x29\x7d\x20\x70\x61\x72\x74\x73\x3d\x7b\x2e\x7b\x20\x2e\x63\x6f\x6e\x74\x65\x6e\x74\x20\x3d\x20\x74\x69\x70\x20\x7d\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x62\x75\x74\x74\x6f\x6e\x7d\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x67\x68\x6f\x73\x74\x7d\x20\x73\x69\x7a\x65\x3d\x7b\x2e\x78\x73\x7d\x20\x69\x63\x6f\x6e\x4f\x6e\x6c\x79\x3d\x7b\x74\x72\x75\x65\x7d\x20\x69\x63\x6f\x6e\x41\x73\x73\x65\x74\x3d\x7b\x75\x69\x2e\x69\x63\x6f\x6e\x73\x2e\x63\x69\x72\x63\x6c\x65\x5f\x68\x65\x6c\x70\x7d\x20\x69\x63\x6f\x6e\x53\x69\x7a\x65\x3d\x7b\x31\x34\x7d\x20\x61\x31\x31\x79\x4c\x61\x62\x65\x6c\x3d\x7b\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x50\x65\x72\x6d\x69\x73\x73\x69\x6f\x6e\x73\x28\x69\x6e\x64\x65\x78\x29\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x73\x65\x74\x50\x6f\x70\x75\x70\x28\x76\x6d\x2c\x20\x74\x69\x70\x2c\x20\x74\x72\x75\x65\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\xe6\x8f\x92\xe4\xbb\xb6\xe4\xbf\xa1\xe6\x81\xaf\xef\xbc\x9a\xe7\x89\x88\xe6\x9c\xac\xe3\x80\x81\xe6\x9d\x83\xe9\x99\x90\xef\xbc\x88\xe6\x97\xa7\xe8\xaf\xa6\xe6\x83\x85\xe7\x9a\x84\xe4\xba\x8b\xe5\xae\x9e\xe8\xa1\x8c\xef\xbc\x9b\xe7\x89\x88\xe6\x9c\xac\xe5\xaf\xb9\xe8\xaf\x9d\xe6\xa1\x86\xe7\x9a\x84\xe2\x80\x9c\xe6\x8f\x92\xe4\xbb\xb6\xe9\x9a\x8f\xe5\xba\x94\xe7\x94\xa8\xe6\x9b\xb4\xe6\x96\xb0\xe2\x80\x9d\xe5\x9c\xa8\xe6\xa6\x82\xe8\xa6\x81\xe7\x9a\x84\xe7\xae\xa1\xe7\x90\x86\xe8\xaf\xb4\xe6\x98\x8e\xe9\x87\x8c\xef\xbc\x89\xe3\x80\x82\x0a\x66\x6e\x20\x46\x61\x63\x74\x73\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x69\x6e\x64\x65\x78\x3a\x20\x75\x38\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x65\x74\x74\x69\x6e\x67\x73\x2e\x70\x6c\x75\x67\x69\x6e\x73\x2e\x69\x6e\x66\x6f\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x70\x61\x6e\x65\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x70\x61\x6e\x65\x5f\x68\x65\x61\x64\x65\x72\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x70\x61\x6e\x65\x5f\x74\x69\x74\x6c\x65\x7d\x3e\xe6\x8f\x92\xe4\xbb\xb6\xe4\xbf\xa1\xe6\x81\xaf\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x42\x6f\x64\x79\x49\x64\x28\x69\x6e\x64\x65\x78\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x70\x61\x6e\x65\x5f\x62\x6f\x64\x79\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x53\x65\x74\x74\x69\x6e\x67\x52\x6f\x77\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x6c\x61\x73\x74\x20\x3d\x20\x66\x61\x6c\x73\x65\x20\x7d\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x6c\x69\x6e\x65\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x6c\x61\x62\x65\x6c\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x69\x6e\x66\x6f\x5f\x6c\x61\x62\x65\x6c\x5f\x62\x6f\x78\x7d\x3e\xe7\x89\x88\xe6\x9c\xac\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x70\x69\x64\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x2c\x20\x2e\x76\x65\x72\x73\x69\x6f\x6e\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x69\x6e\x66\x6f\x5f\x76\x61\x6c\x75\x65\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x69\x6e\x66\x6f\x5f\x76\x61\x6c\x75\x65\x5f\x62\x6f\x78\x7d\x3e\x7b\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x56\x65\x72\x73\x69\x6f\x6e\x28\x69\x6e\x64\x65\x78\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x53\x65\x74\x74\x69\x6e\x67\x52\x6f\x77\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x6c\x61\x73\x74\x20\x3d\x20\x74\x72\x75\x65\x20\x7d\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x6c\x69\x6e\x65\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x68\x65\x61\x64\x69\x6e\x67\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x6c\x61\x62\x65\x6c\x7d\x3e\xe6\x9d\x83\xe9\x99\x90\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x50\x65\x72\x6d\x69\x73\x73\x69\x6f\x6e\x54\x69\x70\x20\x76\x6d\x3d\x7b\x76\x6d\x7d\x20\x69\x6e\x64\x65\x78\x3d\x7b\x69\x6e\x64\x65\x78\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x70\x69\x64\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x2c\x20\x2e\x70\x65\x72\x6d\x69\x73\x73\x69\x6f\x6e\x73\x5f\x76\x61\x6c\x75\x65\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x69\x6e\x66\x6f\x5f\x76\x61\x6c\x75\x65\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x69\x6e\x66\x6f\x5f\x76\x61\x6c\x75\x65\x5f\x62\x6f\x78\x7d\x3e\x7b\x44\x2e\x70\x65\x72\x6d\x69\x73\x73\x69\x6f\x6e\x73\x5f\x76\x61\x6c\x75\x65\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x20\xe2\x94\x80\xe2\x94\x80\x20\xe5\x81\x8f\xe5\xa5\xbd\xe5\xad\x97\xe6\xae\xb5\x20\xe2\x94\x80\xe2\x94\x80\x0a\x0a\x66\x6e\x20\x70\x72\x65\x66\x73\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x69\x6e\x64\x65\x78\x3a\x20\x75\x38\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x6d\x2e\x50\x6c\x75\x67\x69\x6e\x50\x72\x65\x66\x49\x74\x65\x6d\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x50\x72\x65\x66\x49\x74\x65\x6d\x73\x28\x69\x6e\x64\x65\x78\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x68\x61\x73\x50\x72\x65\x66\x73\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x69\x6e\x64\x65\x78\x3a\x20\x75\x38\x29\x20\x62\x6f\x6f\x6c\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x48\x61\x73\x50\x72\x65\x66\x73\x28\x69\x6e\x64\x65\x78\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x66\x69\x64\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x69\x6e\x64\x65\x78\x3a\x20\x75\x38\x2c\x20\x66\x69\x65\x6c\x64\x3a\x20\x75\x38\x2c\x20\x70\x61\x72\x74\x3a\x20\x6d\x2e\x50\x6c\x75\x67\x69\x6e\x50\x72\x65\x66\x50\x61\x72\x74\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x50\x72\x65\x66\x49\x64\x28\x69\x6e\x64\x65\x78\x2c\x20\x66\x69\x65\x6c\x64\x2c\x20\x70\x61\x72\x74\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x69\x73\x4b\x69\x6e\x64\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x69\x6e\x64\x65\x78\x3a\x20\x75\x38\x2c\x20\x66\x69\x65\x6c\x64\x3a\x20\x75\x38\x2c\x20\x6b\x69\x6e\x64\x3a\x20\x6d\x2e\x50\x6c\x75\x67\x69\x6e\x50\x72\x65\x66\x4b\x69\x6e\x64\x29\x20\x62\x6f\x6f\x6c\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x50\x72\x65\x66\x4b\x69\x6e\x64\x28\x69\x6e\x64\x65\x78\x2c\x20\x66\x69\x65\x6c\x64\x29\x20\x3d\x3d\x20\x6b\x69\x6e\x64\x3b\x0a\x7d\x0a\x66\x6e\x20\x74\x69\x6d\x69\x6e\x67\x49\x63\x6f\x6e\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x69\x6e\x64\x65\x78\x3a\x20\x75\x38\x2c\x20\x66\x69\x65\x6c\x64\x3a\x20\x75\x38\x29\x20\x3f\x75\x69\x2e\x53\x76\x67\x41\x73\x73\x65\x74\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x69\x66\x20\x28\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x50\x72\x65\x66\x4e\x65\x78\x74\x43\x6f\x6e\x6e\x65\x63\x74\x69\x6f\x6e\x28\x69\x6e\x64\x65\x78\x2c\x20\x66\x69\x65\x6c\x64\x29\x29\x20\x75\x69\x2e\x69\x63\x6f\x6e\x73\x2e\x63\x6c\x6f\x63\x6b\x5f\x33\x20\x65\x6c\x73\x65\x20\x75\x69\x2e\x69\x63\x6f\x6e\x73\x2e\x63\x69\x72\x63\x6c\x65\x5f\x63\x68\x65\x63\x6b\x3b\x0a\x7d\x0a\x66\x6e\x20\x62\x6f\x6f\x6c\x54\x65\x78\x74\x28\x76\x61\x6c\x75\x65\x3a\x20\x62\x6f\x6f\x6c\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x69\x66\x20\x28\x76\x61\x6c\x75\x65\x29\x20\x22\x74\x72\x75\x65\x22\x20\x65\x6c\x73\x65\x20\x22\x66\x61\x6c\x73\x65\x22\x3b\x0a\x7d\x0a\x66\x6e\x20\x73\x65\x74\x42\x6f\x6f\x6c\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x69\x6e\x64\x65\x78\x3a\x20\x75\x38\x2c\x20\x66\x69\x65\x6c\x64\x3a\x20\x75\x38\x2c\x20\x76\x61\x6c\x75\x65\x3a\x20\x62\x6f\x6f\x6c\x29\x20\x76\x6f\x69\x64\x20\x7b\x0a\x20\x20\x20\x20\x76\x6d\x2e\x64\x69\x73\x70\x61\x74\x63\x68\x28\x6d\x2e\x49\x6e\x74\x65\x6e\x74\x2e\x73\x65\x74\x50\x6c\x75\x67\x69\x6e\x50\x72\x65\x66\x65\x72\x65\x6e\x63\x65\x28\x69\x6e\x64\x65\x78\x2c\x20\x66\x69\x65\x6c\x64\x2c\x20\x62\x6f\x6f\x6c\x54\x65\x78\x74\x28\x76\x61\x6c\x75\x65\x29\x29\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x73\x65\x74\x54\x65\x78\x74\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x69\x6e\x64\x65\x78\x3a\x20\x75\x38\x2c\x20\x66\x69\x65\x6c\x64\x3a\x20\x75\x38\x2c\x20\x74\x65\x78\x74\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x29\x20\x76\x6f\x69\x64\x20\x7b\x0a\x20\x20\x20\x20\x76\x6d\x2e\x64\x69\x73\x70\x61\x74\x63\x68\x28\x6d\x2e\x49\x6e\x74\x65\x6e\x74\x2e\x73\x65\x74\x50\x6c\x75\x67\x69\x6e\x50\x72\x65\x66\x65\x72\x65\x6e\x63\x65\x28\x69\x6e\x64\x65\x78\x2c\x20\x66\x69\x65\x6c\x64\x2c\x20\x74\x65\x78\x74\x29\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x70\x69\x63\x6b\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x69\x6e\x64\x65\x78\x3a\x20\x75\x38\x2c\x20\x66\x69\x65\x6c\x64\x3a\x20\x75\x38\x2c\x20\x76\x61\x6c\x75\x65\x3a\x20\x3f\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x29\x20\x76\x6f\x69\x64\x20\x7b\x0a\x20\x20\x20\x20\x76\x6d\x2e\x64\x69\x73\x70\x61\x74\x63\x68\x28\x6d\x2e\x49\x6e\x74\x65\x6e\x74\x2e\x73\x65\x74\x50\x6c\x75\x67\x69\x6e\x50\x72\x65\x66\x65\x72\x65\x6e\x63\x65\x28\x69\x6e\x64\x65\x78\x2c\x20\x66\x69\x65\x6c\x64\x2c\x20\x76\x61\x6c\x75\x65\x20\x6f\x72\x65\x6c\x73\x65\x20\x72\x65\x74\x75\x72\x6e\x29\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x73\x77\x69\x74\x63\x68\x41\x31\x31\x79\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x69\x6e\x64\x65\x78\x3a\x20\x75\x38\x2c\x20\x66\x69\x65\x6c\x64\x3a\x20\x75\x38\x29\x20\x3f\x75\x69\x2e\x41\x31\x31\x79\x50\x72\x6f\x70\x73\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x2e\x7b\x20\x2e\x72\x6f\x6c\x65\x20\x3d\x20\x2e\x73\x77\x69\x74\x63\x68\x5f\x72\x6f\x6c\x65\x2c\x20\x2e\x6c\x61\x62\x65\x6c\x20\x3d\x20\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x50\x72\x65\x66\x4c\x61\x62\x65\x6c\x28\x69\x6e\x64\x65\x78\x2c\x20\x66\x69\x65\x6c\x64\x29\x2c\x20\x2e\x63\x68\x65\x63\x6b\x65\x64\x20\x3d\x20\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x50\x72\x65\x66\x43\x68\x65\x63\x6b\x65\x64\x28\x69\x6e\x64\x65\x78\x2c\x20\x66\x69\x65\x6c\x64\x29\x2c\x20\x2e\x64\x69\x73\x61\x62\x6c\x65\x64\x20\x3d\x20\x76\x6d\x2e\x69\x73\x53\x61\x76\x69\x6e\x67\x28\x29\x20\x7d\x3b\x0a\x7d\x0a\x66\x6e\x20\x73\x65\x6c\x65\x63\x74\x56\x61\x6c\x75\x65\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x69\x6e\x64\x65\x78\x3a\x20\x75\x38\x2c\x20\x66\x69\x65\x6c\x64\x3a\x20\x75\x38\x29\x20\x3f\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x50\x72\x65\x66\x54\x65\x78\x74\x28\x69\x6e\x64\x65\x78\x2c\x20\x66\x69\x65\x6c\x64\x29\x3b\x0a\x7d\x0a\x2f\x2f\x2f\x20\xe9\x80\x89\xe6\x8b\xa9\xe6\xa1\x86\xe7\x9a\x84\xe9\x80\x89\xe9\xa1\xb9\xef\xbc\x88\xe6\xb3\xa8\xe5\x86\x8c\xe8\xa1\xa8\xe9\x87\x8c\xe7\x9a\x84\xe9\x80\x89\xe9\xa1\xb9\xe6\x8d\xa2\xe6\x88\x90\xe5\x8e\x9f\xe7\x94\x9f\x20\x60\x57\x2e\x53\x65\x6c\x65\x63\x74\x4f\x70\x74\x69\x6f\x6e\x60\xef\xbc\x9b\xe4\xb8\x80\xe4\xb8\xaa\xe8\xaf\xa6\xe6\x83\x85\xe9\xa1\xb5\xe5\x90\x8c\xe6\x97\xb6\xe5\x8f\xaa\xe6\x8c\x82\xe4\xb8\x80\xe4\xb8\xaa\xe6\x8f\x92\xe4\xbb\xb6\xe7\x9a\x84\xe5\xad\x97\xe6\xae\xb5\xef\xbc\x8c\xe6\x8c\x89\xe5\xad\x97\xe6\xae\xb5\xe5\x88\x86\xe6\xa7\xbd\xef\xbc\x89\xe3\x80\x82\x0a\x76\x61\x72\x20\x6f\x70\x74\x69\x6f\x6e\x5f\x62\x75\x66\x66\x65\x72\x3a\x20\x5b\x44\x2e\x6d\x61\x78\x5f\x70\x72\x65\x66\x65\x72\x65\x6e\x63\x65\x73\x5d\x5b\x44\x2e\x6d\x61\x78\x5f\x6f\x70\x74\x69\x6f\x6e\x73\x5d\x57\x2e\x53\x65\x6c\x65\x63\x74\x4f\x70\x74\x69\x6f\x6e\x20\x3d\x20\x75\x6e\x64\x65\x66\x69\x6e\x65\x64\x3b\x0a\x66\x6e\x20\x6f\x70\x74\x69\x6f\x6e\x73\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x69\x6e\x64\x65\x78\x3a\x20\x75\x38\x2c\x20\x66\x69\x65\x6c\x64\x3a\x20\x75\x38\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x57\x2e\x53\x65\x6c\x65\x63\x74\x4f\x70\x74\x69\x6f\x6e\x20\x7b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x63\x6f\x75\x6e\x74\x20\x3d\x20\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x50\x72\x65\x66\x4f\x70\x74\x69\x6f\x6e\x43\x6f\x75\x6e\x74\x28\x69\x6e\x64\x65\x78\x2c\x20\x66\x69\x65\x6c\x64\x29\x3b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x6c\x69\x73\x74\x20\x3d\x20\x26\x6f\x70\x74\x69\x6f\x6e\x5f\x62\x75\x66\x66\x65\x72\x5b\x66\x69\x65\x6c\x64\x5d\x3b\x0a\x20\x20\x20\x20\x66\x6f\x72\x20\x28\x30\x2e\x2e\x63\x6f\x75\x6e\x74\x29\x20\x7c\x6f\x70\x74\x69\x6f\x6e\x7c\x20\x6c\x69\x73\x74\x5b\x6f\x70\x74\x69\x6f\x6e\x5d\x20\x3d\x20\x2e\x7b\x20\x2e\x76\x61\x6c\x75\x65\x20\x3d\x20\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x50\x72\x65\x66\x4f\x70\x74\x69\x6f\x6e\x56\x61\x6c\x75\x65\x28\x69\x6e\x64\x65\x78\x2c\x20\x66\x69\x65\x6c\x64\x2c\x20\x6f\x70\x74\x69\x6f\x6e\x29\x2c\x20\x2e\x6c\x61\x62\x65\x6c\x20\x3d\x20\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x50\x72\x65\x66\x4f\x70\x74\x69\x6f\x6e\x4c\x61\x62\x65\x6c\x28\x69\x6e\x64\x65\x78\x2c\x20\x66\x69\x65\x6c\x64\x2c\x20\x6f\x70\x74\x69\x6f\x6e\x29\x20\x7d\x3b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x6c\x69\x73\x74\x5b\x30\x2e\x2e\x63\x6f\x75\x6e\x74\x5d\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\xe7\x94\x9f\xe6\x95\x88\xe6\x97\xb6\xe6\x9c\xba\xef\xbc\x9a\xe5\x8e\x9f\xe7\x94\x9f\x20\x67\x68\x6f\x73\x74\x20\xe5\x9b\xbe\xe6\xa0\x87\xe6\x8c\x89\xe9\x92\xae\x20\x2b\x20\xe5\x8e\x9f\xe7\x94\x9f\x20\x54\x6f\x6f\x6c\x74\x69\x70\xef\xbc\x88\xe2\x80\x9c\xe4\xb8\x8b\xe6\xac\xa1\xe8\xbf\x9e\xe6\x8e\xa5\xe7\x94\x9f\xe6\x95\x88\xe2\x80\x9d\x20\x2f\x20\xe2\x80\x9c\xe4\xbf\x9d\xe5\xad\x98\xe5\x90\x8e\xe7\x94\x9f\xe6\x95\x88\xe2\x80\x9d\xef\xbc\x9b\xe5\x90\x8c\xe6\x97\xa7\x20\x60\x63\x6f\x6e\x74\x72\x6f\x6c\x73\x2e\x69\x6e\x6c\x69\x6e\x65\x48\x69\x6e\x74\x60\xef\xbc\x89\xe3\x80\x82\x0a\x66\x6e\x20\x54\x69\x6d\x69\x6e\x67\x54\x69\x70\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x69\x6e\x64\x65\x78\x3a\x20\x75\x38\x2c\x20\x66\x69\x65\x6c\x64\x3a\x20\x75\x38\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x74\x69\x70\x20\x3d\x20\x63\x6f\x6d\x70\x75\x74\x65\x64\x28\x66\x69\x64\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x2c\x20\x66\x69\x65\x6c\x64\x2c\x20\x2e\x74\x69\x6d\x69\x6e\x67\x5f\x74\x69\x70\x29\x29\x3b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x62\x75\x74\x74\x6f\x6e\x20\x3d\x20\x63\x6f\x6d\x70\x75\x74\x65\x64\x28\x66\x69\x64\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x2c\x20\x66\x69\x65\x6c\x64\x2c\x20\x2e\x74\x69\x6d\x69\x6e\x67\x29\x29\x3b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x68\x65\x6c\x70\x5f\x73\x6c\x6f\x74\x7d\x20\x6f\x6e\x46\x6f\x63\x75\x73\x3d\x7b\x73\x65\x74\x50\x6f\x70\x75\x70\x28\x76\x6d\x2c\x20\x74\x69\x70\x2c\x20\x74\x72\x75\x65\x29\x7d\x20\x6f\x6e\x42\x6c\x75\x72\x3d\x7b\x73\x65\x74\x50\x6f\x70\x75\x70\x28\x76\x6d\x2c\x20\x74\x69\x70\x2c\x20\x66\x61\x6c\x73\x65\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x20\x74\x65\x78\x74\x3d\x7b\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x50\x72\x65\x66\x54\x69\x6d\x69\x6e\x67\x28\x69\x6e\x64\x65\x78\x2c\x20\x66\x69\x65\x6c\x64\x29\x7d\x20\x70\x6f\x73\x69\x74\x69\x6f\x6e\x3d\x7b\x2e\x74\x6f\x70\x7d\x20\x6f\x70\x65\x6e\x3d\x7b\x70\x6f\x70\x75\x70\x28\x76\x6d\x2c\x20\x74\x69\x70\x29\x7d\x20\x6f\x6e\x4f\x70\x65\x6e\x43\x68\x61\x6e\x67\x65\x3d\x7b\x7c\x6f\x7c\x20\x73\x65\x74\x50\x6f\x70\x75\x70\x28\x76\x6d\x2c\x20\x74\x69\x70\x2c\x20\x6f\x29\x7d\x20\x70\x61\x72\x74\x73\x3d\x7b\x2e\x7b\x20\x2e\x63\x6f\x6e\x74\x65\x6e\x74\x20\x3d\x20\x74\x69\x70\x20\x7d\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x62\x75\x74\x74\x6f\x6e\x7d\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x67\x68\x6f\x73\x74\x7d\x20\x73\x69\x7a\x65\x3d\x7b\x2e\x78\x73\x7d\x20\x69\x63\x6f\x6e\x4f\x6e\x6c\x79\x3d\x7b\x74\x72\x75\x65\x7d\x20\x69\x63\x6f\x6e\x41\x73\x73\x65\x74\x3d\x7b\x74\x69\x6d\x69\x6e\x67\x49\x63\x6f\x6e\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x2c\x20\x66\x69\x65\x6c\x64\x29\x7d\x20\x69\x63\x6f\x6e\x53\x69\x7a\x65\x3d\x7b\x31\x34\x7d\x20\x61\x31\x31\x79\x4c\x61\x62\x65\x6c\x3d\x7b\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x50\x72\x65\x66\x54\x69\x6d\x69\x6e\x67\x28\x69\x6e\x64\x65\x78\x2c\x20\x66\x69\x65\x6c\x64\x29\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x73\x65\x74\x50\x6f\x70\x75\x70\x28\x76\x6d\x2c\x20\x74\x69\x70\x2c\x20\x74\x72\x75\x65\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\xe4\xb8\x80\xe4\xb8\xaa\xe5\x81\x8f\xe5\xa5\xbd\xe5\xad\x97\xe6\xae\xb5\xe8\xa1\x8c\xef\xbc\x9a\xe6\xa0\x87\xe7\xad\xbe\x20\x2b\x20\xe7\x94\x9f\xe6\x95\x88\xe6\x97\xb6\xe6\x9c\xba\xef\xbc\x8c\xe5\x8f\xb3\xe4\xbe\xa7\xe6\x98\xaf\xe6\x8c\x89\xe5\xad\x97\xe6\xae\xb5\xe7\xb1\xbb\xe5\x9e\x8b\xe7\x9a\x84\xe5\x8e\x9f\xe7\x94\x9f\xe6\x8e\xa7\xe4\xbb\xb6\xef\xbc\x9b\xe8\xa2\xab\xe6\x8b\x92\xe7\xbb\x9d\xe7\x9a\x84\xe7\xbc\x96\xe8\xbe\x91\xe5\x9c\xa8\xe8\xa1\x8c\xe4\xb8\x8b\xe6\x8f\x90\xe7\xa4\xba\xe5\x8e\x9f\xe5\x9b\xa0\xe3\x80\x82\x0a\x66\x6e\x20\x50\x72\x65\x66\x52\x6f\x77\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x69\x6e\x64\x65\x78\x3a\x20\x75\x38\x2c\x20\x66\x69\x65\x6c\x64\x3a\x20\x75\x38\x2c\x20\x6c\x61\x73\x74\x3a\x20\x62\x6f\x6f\x6c\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x63\x6f\x6e\x74\x72\x6f\x6c\x20\x3d\x20\x63\x6f\x6d\x70\x75\x74\x65\x64\x28\x66\x69\x64\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x2c\x20\x66\x69\x65\x6c\x64\x2c\x20\x2e\x63\x6f\x6e\x74\x72\x6f\x6c\x29\x29\x3b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x73\x77\x69\x74\x63\x68\x5f\x61\x31\x31\x79\x20\x3d\x20\x63\x6f\x6d\x70\x75\x74\x65\x64\x28\x73\x77\x69\x74\x63\x68\x41\x31\x31\x79\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x2c\x20\x66\x69\x65\x6c\x64\x29\x29\x3b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x66\x69\x64\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x2c\x20\x66\x69\x65\x6c\x64\x2c\x20\x2e\x72\x6f\x77\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x53\x65\x74\x74\x69\x6e\x67\x52\x6f\x77\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x6c\x61\x73\x74\x20\x3d\x20\x6c\x61\x73\x74\x20\x7d\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x6c\x69\x6e\x65\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x63\x6f\x70\x79\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x68\x65\x61\x64\x69\x6e\x67\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x6c\x61\x62\x65\x6c\x7d\x3e\x7b\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x50\x72\x65\x66\x4c\x61\x62\x65\x6c\x28\x69\x6e\x64\x65\x78\x2c\x20\x66\x69\x65\x6c\x64\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x54\x69\x6d\x69\x6e\x67\x54\x69\x70\x20\x76\x6d\x3d\x7b\x76\x6d\x7d\x20\x69\x6e\x64\x65\x78\x3d\x7b\x69\x6e\x64\x65\x78\x7d\x20\x66\x69\x65\x6c\x64\x3d\x7b\x66\x69\x65\x6c\x64\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x7b\x69\x66\x20\x28\x69\x73\x4b\x69\x6e\x64\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x2c\x20\x66\x69\x65\x6c\x64\x2c\x20\x2e\x62\x6f\x6f\x6c\x65\x61\x6e\x29\x29\x20\x3c\x57\x2e\x53\x77\x69\x74\x63\x68\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x63\x6f\x6e\x74\x72\x6f\x6c\x7d\x20\x63\x68\x65\x63\x6b\x65\x64\x3d\x7b\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x50\x72\x65\x66\x43\x68\x65\x63\x6b\x65\x64\x28\x69\x6e\x64\x65\x78\x2c\x20\x66\x69\x65\x6c\x64\x29\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x76\x6d\x2e\x69\x73\x53\x61\x76\x69\x6e\x67\x28\x29\x7d\x20\x61\x31\x31\x79\x3d\x7b\x73\x77\x69\x74\x63\x68\x5f\x61\x31\x31\x79\x7d\x20\x6f\x6e\x43\x68\x61\x6e\x67\x65\x3d\x7b\x7c\x76\x7c\x20\x73\x65\x74\x42\x6f\x6f\x6c\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x2c\x20\x66\x69\x65\x6c\x64\x2c\x20\x76\x29\x7d\x20\x2f\x3e\x20\x65\x6c\x73\x65\x20\x69\x66\x20\x28\x69\x73\x4b\x69\x6e\x64\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x2c\x20\x66\x69\x65\x6c\x64\x2c\x20\x2e\x73\x74\x72\x69\x6e\x67\x29\x29\x20\x3c\x57\x2e\x49\x6e\x70\x75\x74\x20\x76\x61\x6c\x75\x65\x3d\x7b\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x50\x72\x65\x66\x54\x65\x78\x74\x28\x69\x6e\x64\x65\x78\x2c\x20\x66\x69\x65\x6c\x64\x29\x7d\x20\x77\x69\x64\x74\x68\x3d\x7b\x31\x38\x30\x7d\x20\x69\x6e\x76\x61\x6c\x69\x64\x3d\x7b\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x50\x72\x65\x66\x49\x6e\x76\x61\x6c\x69\x64\x28\x69\x6e\x64\x65\x78\x2c\x20\x66\x69\x65\x6c\x64\x29\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x76\x6d\x2e\x69\x73\x53\x61\x76\x69\x6e\x67\x28\x29\x7d\x20\x6f\x6e\x43\x68\x61\x6e\x67\x65\x3d\x7b\x7c\x74\x7c\x20\x73\x65\x74\x54\x65\x78\x74\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x2c\x20\x66\x69\x65\x6c\x64\x2c\x20\x74\x29\x7d\x20\x6f\x6e\x53\x75\x62\x6d\x69\x74\x3d\x7b\x7c\x74\x7c\x20\x73\x65\x74\x54\x65\x78\x74\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x2c\x20\x66\x69\x65\x6c\x64\x2c\x20\x74\x29\x7d\x20\x70\x61\x72\x74\x73\x3d\x7b\x2e\x7b\x20\x2e\x69\x6e\x70\x75\x74\x5f\x63\x6f\x6e\x74\x61\x69\x6e\x65\x72\x20\x3d\x20\x63\x6f\x6e\x74\x72\x6f\x6c\x20\x7d\x7d\x20\x2f\x3e\x20\x65\x6c\x73\x65\x20\x3c\x57\x2e\x53\x65\x6c\x65\x63\x74\x20\x70\x61\x6e\x65\x6c\x57\x69\x64\x74\x68\x3d\x7b\x2e\x74\x72\x69\x67\x67\x65\x72\x7d\x20\x6f\x70\x74\x69\x6f\x6e\x73\x3d\x7b\x6f\x70\x74\x69\x6f\x6e\x73\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x2c\x20\x66\x69\x65\x6c\x64\x29\x7d\x20\x76\x61\x6c\x75\x65\x3d\x7b\x73\x65\x6c\x65\x63\x74\x56\x61\x6c\x75\x65\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x2c\x20\x66\x69\x65\x6c\x64\x29\x7d\x20\x77\x69\x64\x74\x68\x3d\x7b\x31\x38\x30\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x76\x6d\x2e\x69\x73\x53\x61\x76\x69\x6e\x67\x28\x29\x7d\x20\x6f\x70\x65\x6e\x3d\x7b\x70\x6f\x70\x75\x70\x28\x76\x6d\x2c\x20\x63\x6f\x6e\x74\x72\x6f\x6c\x29\x7d\x20\x6f\x6e\x4f\x70\x65\x6e\x43\x68\x61\x6e\x67\x65\x3d\x7b\x7c\x6f\x7c\x20\x73\x65\x74\x50\x6f\x70\x75\x70\x28\x76\x6d\x2c\x20\x63\x6f\x6e\x74\x72\x6f\x6c\x2c\x20\x6f\x29\x7d\x20\x6f\x6e\x43\x68\x61\x6e\x67\x65\x3d\x7b\x7c\x76\x7c\x20\x70\x69\x63\x6b\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x2c\x20\x66\x69\x65\x6c\x64\x2c\x20\x76\x29\x7d\x20\x70\x61\x72\x74\x73\x3d\x7b\x2e\x7b\x20\x2e\x74\x72\x69\x67\x67\x65\x72\x20\x3d\x20\x63\x6f\x6e\x74\x72\x6f\x6c\x20\x7d\x7d\x20\x2f\x3e\x7d\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x66\x69\x64\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x2c\x20\x66\x69\x65\x6c\x64\x2c\x20\x2e\x65\x72\x72\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x65\x72\x72\x6f\x72\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x50\x72\x65\x66\x49\x6e\x76\x61\x6c\x69\x64\x28\x69\x6e\x64\x65\x78\x2c\x20\x66\x69\x65\x6c\x64\x29\x7d\x3e\x7b\x76\x6d\x2e\x70\x6c\x75\x67\x69\x6e\x50\x72\x65\x66\x50\x72\x6f\x62\x6c\x65\x6d\x28\x69\x6e\x64\x65\x78\x2c\x20\x66\x69\x65\x6c\x64\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\xe6\x8f\x92\xe4\xbb\xb6\xe8\x87\xaa\xe5\xb8\xa6\xe7\x9a\x84\xe8\xae\xbe\xe7\xbd\xae\xef\xbc\x88\xe6\x97\xa7\xe8\xaf\xa6\xe6\x83\x85\xe9\x9d\xa2\xe6\x9d\xbf\xe9\x87\x8c\xe7\x9a\x84\xe5\x81\x8f\xe5\xa5\xbd\xe8\xa1\x8c\xef\xbc\x89\xe3\x80\x82\x0a\x66\x6e\x20\x50\x72\x65\x66\x65\x72\x65\x6e\x63\x65\x73\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x69\x6e\x64\x65\x78\x3a\x20\x75\x38\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x65\x74\x74\x69\x6e\x67\x73\x2e\x70\x6c\x75\x67\x69\x6e\x73\x2e\x70\x72\x65\x66\x65\x72\x65\x6e\x63\x65\x73\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x70\x61\x6e\x65\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x68\x61\x73\x50\x72\x65\x66\x73\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x70\x61\x6e\x65\x5f\x68\x65\x61\x64\x65\x72\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x70\x61\x6e\x65\x5f\x74\x69\x74\x6c\x65\x7d\x3e\xe5\x81\x8f\xe5\xa5\xbd\xe8\xae\xbe\xe7\xbd\xae\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x70\x61\x6e\x65\x5f\x62\x6f\x64\x79\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x7b\x66\x6f\x72\x20\x28\x70\x72\x65\x66\x73\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x29\x29\x20\x7c\x69\x74\x65\x6d\x7c\x20\x3c\x50\x72\x65\x66\x52\x6f\x77\x20\x6b\x65\x79\x3d\x7b\x69\x74\x65\x6d\x2e\x6b\x65\x79\x7d\x20\x76\x6d\x3d\x7b\x76\x6d\x7d\x20\x69\x6e\x64\x65\x78\x3d\x7b\x69\x6e\x64\x65\x78\x7d\x20\x66\x69\x65\x6c\x64\x3d\x7b\x69\x74\x65\x6d\x2e\x66\x69\x65\x6c\x64\x7d\x20\x6c\x61\x73\x74\x3d\x7b\x69\x74\x65\x6d\x2e\x6c\x61\x73\x74\x7d\x20\x2f\x3e\x7d\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x66\x6e\x20\x44\x65\x74\x61\x69\x6c\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x69\x6e\x64\x65\x78\x3a\x20\x75\x38\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x70\x69\x64\x28\x76\x6d\x2c\x20\x69\x6e\x64\x65\x78\x2c\x20\x2e\x64\x65\x74\x61\x69\x6c\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x50\x2e\x70\x61\x6e\x65\x73\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x53\x75\x6d\x6d\x61\x72\x79\x20\x76\x6d\x3d\x7b\x76\x6d\x7d\x20\x69\x6e\x64\x65\x78\x3d\x7b\x69\x6e\x64\x65\x78\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x53\x74\x61\x74\x75\x73\x20\x76\x6d\x3d\x7b\x76\x6d\x7d\x20\x69\x6e\x64\x65\x78\x3d\x7b\x69\x6e\x64\x65\x78\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x46\x61\x63\x74\x73\x20\x76\x6d\x3d\x7b\x76\x6d\x7d\x20\x69\x6e\x64\x65\x78\x3d\x7b\x69\x6e\x64\x65\x78\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x50\x72\x65\x66\x65\x72\x65\x6e\x63\x65\x73\x20\x76\x6d\x3d\x7b\x76\x6d\x7d\x20\x69\x6e\x64\x65\x78\x3d\x7b\x69\x6e\x64\x65\x78\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x70\x75\x62\x20\x66\x6e\x20\x50\x6c\x75\x67\x69\x6e\x73\x50\x61\x6e\x65\x73\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x65\x74\x74\x69\x6e\x67\x73\x2e\x70\x6c\x75\x67\x69\x6e\x73\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x63\x61\x74\x65\x67\x6f\x72\x79\x5f\x70\x61\x6e\x65\x73\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x7b\x69\x66\x20\x28\x64\x65\x74\x61\x69\x6c\x53\x68\x6f\x77\x6e\x28\x76\x6d\x29\x29\x20\x3c\x44\x65\x74\x61\x69\x6c\x20\x76\x6d\x3d\x7b\x76\x6d\x7d\x20\x69\x6e\x64\x65\x78\x3d\x7b\x64\x65\x74\x61\x69\x6c\x49\x6e\x64\x65\x78\x28\x76\x6d\x29\x7d\x20\x2f\x3e\x20\x65\x6c\x73\x65\x20\x3c\x4c\x69\x73\x74\x20\x76\x6d\x3d\x7b\x76\x6d\x7d\x20\x2f\x3e\x7d\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x63\x6f\x6d\x70\x74\x69\x6d\x65\x20\x7b\x0a\x20\x20\x20\x20\x5f\x20\x3d\x20\x73\x74\x64\x3b\x0a\x7d\x0a" else null;
const __YixStyleCatalog = if (ui.view.template.preview_enabled) ui.view.template.styleCatalog(.{ .@"S " = S, .@"P " = P, .@"D " = D, }) else void;

//# yix-map-data [[2886,2871],[12403,3929],[20340,4659],[25590,5138],[31960,6124],[48719,8457],[72332,10607],[82003,11471],[95106,15054],[105614,15934],[131531,17694],[138068,18192],[142805,18528]]

//# yix-map plugins.yix
