// GENERATED FILE, do not edit: generated from subtree_order.yix; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! Runtime fixture: a {for} row or an {if} / {switch} branch whose own derived values read the
//! same signal as the list / condition (ZeroWork G21). Removing the row or unloading the branch
//! must come first: the row's `name(vm, row.i)` with the new page and an old index is out of range.
//! Lives outside tests/yix so it is not an LP3 equivalence input (those need reviewed goldens).
const ui = @import("ui");

pub const Vm = struct {
    page: *ui.Signal(u8),
    /// Selected entry of page 0, null when nothing is picked.
    pick: *ui.Signal(?u8),
    tab: *ui.Signal(Tab),
};
pub const Tab = enum { list, empty };
pub const Item = struct { i: u8 };

const page_items = [_][]const Item{
    &.{ .{ .i = 0 }, .{ .i = 1 }, .{ .i = 2 } },
    &.{.{ .i = 0 }},
};
const page_names = [_][]const []const u8{
    &.{ "a0", "a1", "a2" },
    &.{"b0"},
};

/// Counts reads that would have indexed past the end (the downstream code panics there).
pub var stale_reads: u32 = 0;

fn items(vm: *Vm) []const Item {
    return page_items[vm.page.get()];
}
fn name(vm: *Vm, i: u8) []const u8 {
    const names = page_names[vm.page.get()];
    if (i >= names.len) {
        stale_reads += 1;
        return "stale";
    }
    return names[i];
}
fn picked(vm: *Vm) bool {
    return vm.pick.get() != null;
}
fn pickedName(vm: *Vm) []const u8 {
    const i = vm.pick.get() orelse {
        stale_reads += 1;
        return "stale";
    };
    return page_names[0][i];
}
fn tab(vm: *Vm) Tab {
    return vm.tab.get();
}
fn firstName(vm: *Vm) []const u8 {
    if (vm.tab.get() != .list) {
        stale_reads += 1;
        return "stale";
    }
    return page_names[0][0];
}

/// The row written inline in {for}: its text reads the page signal and the row variable.
pub fn InlineRows(args: anytype) ui.view.ComponentOf(__yix_InlineRows) {
    return ui.view.component(__yix_InlineRows, ui.reactive.props.coerce(InlineRowsProps, args));
}
pub const InlineRowsProps = struct {
    vm: ui.Source(*Vm),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = InlineRows;
    pub const __yix_preview_mount = __yix_InlineRows;
};
fn __yix_InlineRows(__yix_props: InlineRowsProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tests/yix_runtime/subtree_order.yix", .path = "InlineRows", .receiver = "col", .tokens = "col ", .literal_text = null, .attributes = &.{ }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .vm = __yix_view_ctx.vm, }, ui.view.col(.{ }, .{
            ui.view.templateSite(.{ .module = "tests/yix_runtime/subtree_order.yix", .path = "InlineRows", .receiver = "control", .tokens = "for ( items ( vm ) ) | row | < text key = { row . i } > { name ( vm , row . i ) } < / text > " }, .{ .vm = __yix_view_ctx.vm, }, __yix_e1: { const __yix_items_1 = __yix_d2: {
        const __yix_T = @TypeOf(items(__yix_view_ctx.vm.peek()));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return items(__yix_ctx.vm.get());
        } }.__yix_compute);
    }; break :__yix_e1 ui.view.eachWith(.{ .vm = __yix_view_ctx.vm, }, __yix_items_1, struct { fn __yix_k(row: ui.view.yixItem(@TypeOf(__yix_items_1))) u64 { return ui.view.keyOf(row.i); } }.__yix_k, struct { fn __yix_row(__yix_row_1: anytype, row: ui.Source(ui.view.yixItem(@TypeOf(__yix_items_1))), __yix_scope_1: *ui.Scope, __yix_cx_1: *ui.Cx) anyerror!*ui.Node { return ui.view.render(__yix_scope_1, __yix_cx_1, ui.view.templateSite(.{ .module = "tests/yix_runtime/subtree_order.yix", .path = "InlineRows/keyword_for:1", .receiver = "text", .tokens = "text key = row . i ; name ( vm , row . i )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "key", .tokens = "row . i ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_row_1.vm, .row = row, }, ui.view.text(.{ }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d1: {
        const __yix_T = @TypeOf(name(__yix_row_1.vm.peek(), row.peek().i));
        break :__yix_d1 try __yix_scope_1.derive(__yix_T, .{ .vm = __yix_row_1.vm, .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return name(__yix_ctx.vm.get(), __yix_ctx.row.get().i);
        } }.__yix_compute);
    }), ""), .{ __yix_d1: {
        const __yix_T = @TypeOf(name(__yix_row_1.vm.peek(), row.peek().i));
        break :__yix_d1 try __yix_scope_1.derive(__yix_T, .{ .vm = __yix_row_1.vm, .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return name(__yix_ctx.vm.get(), __yix_ctx.row.get().i);
        } }.__yix_compute);
    }, })))); } }.__yix_row); }),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "InlineRows";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

fn Row(args: anytype) ui.view.ComponentOf(__yix_Row) {
    return ui.view.component(__yix_Row, ui.reactive.props.coerce(RowProps, args));
}
const RowProps = struct {
    vm: ui.Source(*Vm),
    i: ui.Source(u8),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = Row;
    pub const __yix_preview_mount = __yix_Row;
};
fn __yix_Row(__yix_props: RowProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    const i = __yix_props.i;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, .i = i, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tests/yix_runtime/subtree_order.yix", .path = "Row", .receiver = "text", .tokens = "text name ( vm , i )  @interpolation ", .literal_text = null, .attributes = &.{ }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .vm = __yix_view_ctx.vm, .i = __yix_view_ctx.i, }, ui.view.text(.{ }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d1: {
        const __yix_T = @TypeOf(name(__yix_view_ctx.vm.peek(), __yix_view_ctx.i.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .i = __yix_view_ctx.i, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return name(__yix_ctx.vm.get(), __yix_ctx.i.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d1: {
        const __yix_T = @TypeOf(name(__yix_view_ctx.vm.peek(), __yix_view_ctx.i.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .i = __yix_view_ctx.i, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return name(__yix_ctx.vm.get(), __yix_ctx.i.get());
        } }.__yix_compute);
    }, }))));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "Row";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

/// The same row as a row component.
pub fn ComponentRows(args: anytype) ui.view.ComponentOf(__yix_ComponentRows) {
    return ui.view.component(__yix_ComponentRows, ui.reactive.props.coerce(ComponentRowsProps, args));
}
pub const ComponentRowsProps = struct {
    vm: ui.Source(*Vm),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = ComponentRows;
    pub const __yix_preview_mount = __yix_ComponentRows;
};
fn __yix_ComponentRows(__yix_props: ComponentRowsProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tests/yix_runtime/subtree_order.yix", .path = "ComponentRows", .receiver = "col", .tokens = "col ", .literal_text = null, .attributes = &.{ }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .vm = __yix_view_ctx.vm, }, ui.view.col(.{ }, .{
            ui.view.templateSite(.{ .module = "tests/yix_runtime/subtree_order.yix", .path = "ComponentRows", .receiver = "control", .tokens = "for ( items ( vm ) ) | row | < Row key = { row . i } vm = { vm } i = { row . i } / > " }, .{ .vm = __yix_view_ctx.vm, }, __yix_e1: { const __yix_items_1 = __yix_d2: {
        const __yix_T = @TypeOf(items(__yix_view_ctx.vm.peek()));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return items(__yix_ctx.vm.get());
        } }.__yix_compute);
    }; break :__yix_e1 ui.view.eachWith(.{ .vm = __yix_view_ctx.vm, }, __yix_items_1, struct { fn __yix_k(row: ui.view.yixItem(@TypeOf(__yix_items_1))) u64 { return ui.view.keyOf(row.i); } }.__yix_k, struct { fn __yix_row(__yix_row_1: anytype, row: ui.Source(ui.view.yixItem(@TypeOf(__yix_items_1))), __yix_scope_1: *ui.Scope, __yix_cx_1: *ui.Cx) anyerror!*ui.Node { return ui.view.render(__yix_scope_1, __yix_cx_1, ui.view.templateSite(.{ .module = "tests/yix_runtime/subtree_order.yix", .path = "ComponentRows/keyword_for:1", .receiver = "Row", .tokens = "< Row key = { row . i } vm = { vm } i = { row . i } / > ", .literal_text = null, .attributes = &.{ .{ .name = "key", .tokens = "row . i ", .kind = .property, .literal = null }, .{ .name = "vm", .tokens = "vm ", .kind = .property, .literal = null }, .{ .name = "i", .tokens = "row . i ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_row_1.vm, .row = row, }, __yix_builder_22: { try ui.view.previewCheckBuilder(__yix_scope_1, Row); break :__yix_builder_22 Row(.{ .vm = __yix_row_1.vm, .i = __yix_d1: {
        const __yix_T = if (ui.view.attrType(Row, "i")) |__yix_A| __yix_A else @TypeOf(row.peek().i);
        break :__yix_d1 try __yix_scope_1.derive(__yix_T, .{ .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.row.get().i;
        } }.__yix_compute);
    }, }); })); } }.__yix_row); }),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "ComponentRows";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

/// A row inside a row: the inner list and the inner text both read the page signal.
pub fn NestedRows(args: anytype) ui.view.ComponentOf(__yix_NestedRows) {
    return ui.view.component(__yix_NestedRows, ui.reactive.props.coerce(NestedRowsProps, args));
}
pub const NestedRowsProps = struct {
    vm: ui.Source(*Vm),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = NestedRows;
    pub const __yix_preview_mount = __yix_NestedRows;
};
fn __yix_NestedRows(__yix_props: NestedRowsProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tests/yix_runtime/subtree_order.yix", .path = "NestedRows", .receiver = "col", .tokens = "col ", .literal_text = null, .attributes = &.{ }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .vm = __yix_view_ctx.vm, }, ui.view.col(.{ }, .{
            ui.view.templateSite(.{ .module = "tests/yix_runtime/subtree_order.yix", .path = "NestedRows", .receiver = "control", .tokens = "for ( items ( vm ) ) | row | < col key = { row . i } > { for ( items ( vm ) ) | cell | < text key = { cell . i } > { name ( vm , cell . i ) } < / text > } < / col > " }, .{ .vm = __yix_view_ctx.vm, }, __yix_e1: { const __yix_items_1 = __yix_d1: {
        const __yix_T = @TypeOf(items(__yix_view_ctx.vm.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return items(__yix_ctx.vm.get());
        } }.__yix_compute);
    }; break :__yix_e1 ui.view.eachWith(.{ .vm = __yix_view_ctx.vm, }, __yix_items_1, struct { fn __yix_k(row: ui.view.yixItem(@TypeOf(__yix_items_1))) u64 { return ui.view.keyOf(row.i); } }.__yix_k, struct { fn __yix_row(__yix_row_1: anytype, row: ui.Source(ui.view.yixItem(@TypeOf(__yix_items_1))), __yix_scope_1: *ui.Scope, __yix_cx_1: *ui.Cx) anyerror!*ui.Node { _ = row; return ui.view.render(__yix_scope_1, __yix_cx_1, ui.view.templateSite(.{ .module = "tests/yix_runtime/subtree_order.yix", .path = "NestedRows/keyword_for:1", .receiver = "col", .tokens = "col key = row . i ; ", .literal_text = null, .attributes = &.{ .{ .name = "key", .tokens = "row . i ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_row_1.vm, }, ui.view.col(.{ }, .{
                    ui.view.templateSite(.{ .module = "tests/yix_runtime/subtree_order.yix", .path = "NestedRows/keyword_for:1", .receiver = "control", .tokens = "for ( items ( vm ) ) | cell | < text key = { cell . i } > { name ( vm , cell . i ) } < / text > " }, .{ .vm = __yix_row_1.vm, }, __yix_e2: { const __yix_items_2 = __yix_d2: {
        const __yix_T = @TypeOf(items(__yix_row_1.vm.peek()));
        break :__yix_d2 try __yix_scope_1.derive(__yix_T, .{ .vm = __yix_row_1.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return items(__yix_ctx.vm.get());
        } }.__yix_compute);
    }; break :__yix_e2 ui.view.eachWith(.{ .vm = __yix_row_1.vm, }, __yix_items_2, struct { fn __yix_k(cell: ui.view.yixItem(@TypeOf(__yix_items_2))) u64 { return ui.view.keyOf(cell.i); } }.__yix_k, struct { fn __yix_row(__yix_row_2: anytype, cell: ui.Source(ui.view.yixItem(@TypeOf(__yix_items_2))), __yix_scope_2: *ui.Scope, __yix_cx_2: *ui.Cx) anyerror!*ui.Node { return ui.view.render(__yix_scope_2, __yix_cx_2, ui.view.templateSite(.{ .module = "tests/yix_runtime/subtree_order.yix", .path = "NestedRows/keyword_for:1/keyword_for:2", .receiver = "text", .tokens = "text key = cell . i ; name ( vm , cell . i )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "key", .tokens = "cell . i ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_row_2.vm, .cell = cell, }, ui.view.text(.{ }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d1: {
        const __yix_T = @TypeOf(name(__yix_row_2.vm.peek(), cell.peek().i));
        break :__yix_d1 try __yix_scope_2.derive(__yix_T, .{ .vm = __yix_row_2.vm, .cell = cell, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return name(__yix_ctx.vm.get(), __yix_ctx.cell.get().i);
        } }.__yix_compute);
    }), ""), .{ __yix_d1: {
        const __yix_T = @TypeOf(name(__yix_row_2.vm.peek(), cell.peek().i));
        break :__yix_d1 try __yix_scope_2.derive(__yix_T, .{ .vm = __yix_row_2.vm, .cell = cell, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return name(__yix_ctx.vm.get(), __yix_ctx.cell.get().i);
        } }.__yix_compute);
    }, })))); } }.__yix_row); }),
                }))); } }.__yix_row); }),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "NestedRows";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

/// An {if} branch whose text reads the condition's signal.
pub fn Picked(args: anytype) ui.view.ComponentOf(__yix_Picked) {
    return ui.view.component(__yix_Picked, ui.reactive.props.coerce(PickedProps, args));
}
pub const PickedProps = struct {
    vm: ui.Source(*Vm),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = Picked;
    pub const __yix_preview_mount = __yix_Picked;
};
fn __yix_Picked(__yix_props: PickedProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tests/yix_runtime/subtree_order.yix", .path = "Picked", .receiver = "col", .tokens = "col ", .literal_text = null, .attributes = &.{ }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .vm = __yix_view_ctx.vm, }, ui.view.col(.{ }, .{
            ui.view.templateSite(.{ .module = "tests/yix_runtime/subtree_order.yix", .path = "Picked", .receiver = "control", .tokens = "if ( picked ( vm ) ) < text > { pickedName ( vm ) } < / text > else < text > none < / text > " }, .{ .vm = __yix_view_ctx.vm, }, ui.view.lazyIf(__yix_d2: {
        const __yix_T = @TypeOf(picked(__yix_view_ctx.vm.peek()));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return picked(__yix_ctx.vm.get());
        } }.__yix_compute);
    }, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_b(__yix_b1_0: anytype, __yix_bs1_0: *ui.Scope, __yix_bc1_0: *ui.Cx, __yix_bk1_0: ui.view.Sink) anyerror!void { return ui.view.emit(__yix_bs1_0, __yix_bc1_0, __yix_bk1_0, .{ ui.view.templateSite(.{ .module = "tests/yix_runtime/subtree_order.yix", .path = "Picked/keyword_if:1/branch:0", .receiver = "text", .tokens = "text pickedName ( vm )  @interpolation ", .literal_text = null, .attributes = &.{ } }, .{ .vm = __yix_b1_0.vm, }, ui.view.text(.{ }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d1: {
        const __yix_T = @TypeOf(pickedName(__yix_b1_0.vm.peek()));
        break :__yix_d1 try __yix_bs1_0.derive(__yix_T, .{ .vm = __yix_b1_0.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return pickedName(__yix_ctx.vm.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d1: {
        const __yix_T = @TypeOf(pickedName(__yix_b1_0.vm.peek()));
        break :__yix_d1 try __yix_bs1_0.derive(__yix_T, .{ .vm = __yix_b1_0.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return pickedName(__yix_ctx.vm.get());
        } }.__yix_compute);
    }, }))) }); } }.__yix_b, struct { fn __yix_b(__yix_b1_1: anytype, __yix_bs1_1: *ui.Scope, __yix_bc1_1: *ui.Cx, __yix_bk1_1: ui.view.Sink) anyerror!void { _ = __yix_b1_1; return ui.view.emit(__yix_bs1_1, __yix_bc1_1, __yix_bk1_1, .{ ui.view.templateSite(.{ .module = "tests/yix_runtime/subtree_order.yix", .path = "Picked/keyword_if:1/branch:1", .receiver = "text", .tokens = "text ", .literal_text = "none", .attributes = &.{ } }, .{ }, ui.view.text(.{ }, ui.view.fmt("none", .{ }))) }); } }.__yix_b)),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "Picked";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

/// A {switch} branch whose text reads the switched signal.
pub fn Tabs(args: anytype) ui.view.ComponentOf(__yix_Tabs) {
    return ui.view.component(__yix_Tabs, ui.reactive.props.coerce(TabsProps, args));
}
pub const TabsProps = struct {
    vm: ui.Source(*Vm),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = Tabs;
    pub const __yix_preview_mount = __yix_Tabs;
};
fn __yix_Tabs(__yix_props: TabsProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tests/yix_runtime/subtree_order.yix", .path = "Tabs", .receiver = "col", .tokens = "col ", .literal_text = null, .attributes = &.{ }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .vm = __yix_view_ctx.vm, }, ui.view.col(.{ }, .{
            ui.view.templateSite(.{ .module = "tests/yix_runtime/subtree_order.yix", .path = "Tabs", .receiver = "control", .tokens = "switch ( tab ( vm ) ) { . list => < text > { firstName ( vm ) } < / text > , . empty => < text > empty < / text > } " }, .{ .vm = __yix_view_ctx.vm, }, ui.view.lazySwitch(__yix_d2: {
        const __yix_T = @TypeOf(tab(__yix_view_ctx.vm.peek()));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return tab(__yix_ctx.vm.get());
        } }.__yix_compute);
    }, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_b(__yix_b1_0: anytype, __yix_bt1_0: anytype, __yix_bv1_0: anytype, __yix_bs1_0: *ui.Scope, __yix_bc1_0: *ui.Cx, __yix_bk1_0: ui.view.Sink) anyerror!void { _ = __yix_bv1_0; switch (__yix_bt1_0) { .list => { return ui.view.emit(__yix_bs1_0, __yix_bc1_0, __yix_bk1_0, .{ ui.view.templateSite(.{ .module = "tests/yix_runtime/subtree_order.yix", .path = "Tabs/keyword_switch:1/case:.list", .receiver = "text", .tokens = "text firstName ( vm )  @interpolation ", .literal_text = null, .attributes = &.{ } }, .{ .vm = __yix_b1_0.vm, }, ui.view.text(.{ }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d1: {
        const __yix_T = @TypeOf(firstName(__yix_b1_0.vm.peek()));
        break :__yix_d1 try __yix_bs1_0.derive(__yix_T, .{ .vm = __yix_b1_0.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return firstName(__yix_ctx.vm.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d1: {
        const __yix_T = @TypeOf(firstName(__yix_b1_0.vm.peek()));
        break :__yix_d1 try __yix_bs1_0.derive(__yix_T, .{ .vm = __yix_b1_0.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return firstName(__yix_ctx.vm.get());
        } }.__yix_compute);
    }, }))) }); }, .empty => { return ui.view.emit(__yix_bs1_0, __yix_bc1_0, __yix_bk1_0, .{ ui.view.templateSite(.{ .module = "tests/yix_runtime/subtree_order.yix", .path = "Tabs/keyword_switch:1/case:.empty", .receiver = "text", .tokens = "text ", .literal_text = "empty", .attributes = &.{ } }, .{ }, ui.view.text(.{ }, ui.view.fmt("empty", .{ }))) }); }, } } }.__yix_b)),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "Tabs";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

const __yix_preview_source: ?[]const u8 = if (ui.view.template.preview_enabled) "\x2f\x2f\x21\x20\x52\x75\x6e\x74\x69\x6d\x65\x20\x66\x69\x78\x74\x75\x72\x65\x3a\x20\x61\x20\x7b\x66\x6f\x72\x7d\x20\x72\x6f\x77\x20\x6f\x72\x20\x61\x6e\x20\x7b\x69\x66\x7d\x20\x2f\x20\x7b\x73\x77\x69\x74\x63\x68\x7d\x20\x62\x72\x61\x6e\x63\x68\x20\x77\x68\x6f\x73\x65\x20\x6f\x77\x6e\x20\x64\x65\x72\x69\x76\x65\x64\x20\x76\x61\x6c\x75\x65\x73\x20\x72\x65\x61\x64\x20\x74\x68\x65\x0a\x2f\x2f\x21\x20\x73\x61\x6d\x65\x20\x73\x69\x67\x6e\x61\x6c\x20\x61\x73\x20\x74\x68\x65\x20\x6c\x69\x73\x74\x20\x2f\x20\x63\x6f\x6e\x64\x69\x74\x69\x6f\x6e\x20\x28\x5a\x65\x72\x6f\x57\x6f\x72\x6b\x20\x47\x32\x31\x29\x2e\x20\x52\x65\x6d\x6f\x76\x69\x6e\x67\x20\x74\x68\x65\x20\x72\x6f\x77\x20\x6f\x72\x20\x75\x6e\x6c\x6f\x61\x64\x69\x6e\x67\x20\x74\x68\x65\x20\x62\x72\x61\x6e\x63\x68\x0a\x2f\x2f\x21\x20\x6d\x75\x73\x74\x20\x63\x6f\x6d\x65\x20\x66\x69\x72\x73\x74\x3a\x20\x74\x68\x65\x20\x72\x6f\x77\x27\x73\x20\x60\x6e\x61\x6d\x65\x28\x76\x6d\x2c\x20\x72\x6f\x77\x2e\x69\x29\x60\x20\x77\x69\x74\x68\x20\x74\x68\x65\x20\x6e\x65\x77\x20\x70\x61\x67\x65\x20\x61\x6e\x64\x20\x61\x6e\x20\x6f\x6c\x64\x20\x69\x6e\x64\x65\x78\x20\x69\x73\x20\x6f\x75\x74\x20\x6f\x66\x20\x72\x61\x6e\x67\x65\x2e\x0a\x2f\x2f\x21\x20\x4c\x69\x76\x65\x73\x20\x6f\x75\x74\x73\x69\x64\x65\x20\x74\x65\x73\x74\x73\x2f\x79\x69\x78\x20\x73\x6f\x20\x69\x74\x20\x69\x73\x20\x6e\x6f\x74\x20\x61\x6e\x20\x4c\x50\x33\x20\x65\x71\x75\x69\x76\x61\x6c\x65\x6e\x63\x65\x20\x69\x6e\x70\x75\x74\x20\x28\x74\x68\x6f\x73\x65\x20\x6e\x65\x65\x64\x20\x72\x65\x76\x69\x65\x77\x65\x64\x20\x67\x6f\x6c\x64\x65\x6e\x73\x29\x2e\x0a\x63\x6f\x6e\x73\x74\x20\x75\x69\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x75\x69\x22\x29\x3b\x0a\x0a\x70\x75\x62\x20\x63\x6f\x6e\x73\x74\x20\x56\x6d\x20\x3d\x20\x73\x74\x72\x75\x63\x74\x20\x7b\x0a\x20\x20\x20\x20\x70\x61\x67\x65\x3a\x20\x2a\x75\x69\x2e\x53\x69\x67\x6e\x61\x6c\x28\x75\x38\x29\x2c\x0a\x20\x20\x20\x20\x2f\x2f\x2f\x20\x53\x65\x6c\x65\x63\x74\x65\x64\x20\x65\x6e\x74\x72\x79\x20\x6f\x66\x20\x70\x61\x67\x65\x20\x30\x2c\x20\x6e\x75\x6c\x6c\x20\x77\x68\x65\x6e\x20\x6e\x6f\x74\x68\x69\x6e\x67\x20\x69\x73\x20\x70\x69\x63\x6b\x65\x64\x2e\x0a\x20\x20\x20\x20\x70\x69\x63\x6b\x3a\x20\x2a\x75\x69\x2e\x53\x69\x67\x6e\x61\x6c\x28\x3f\x75\x38\x29\x2c\x0a\x20\x20\x20\x20\x74\x61\x62\x3a\x20\x2a\x75\x69\x2e\x53\x69\x67\x6e\x61\x6c\x28\x54\x61\x62\x29\x2c\x0a\x7d\x3b\x0a\x70\x75\x62\x20\x63\x6f\x6e\x73\x74\x20\x54\x61\x62\x20\x3d\x20\x65\x6e\x75\x6d\x20\x7b\x20\x6c\x69\x73\x74\x2c\x20\x65\x6d\x70\x74\x79\x20\x7d\x3b\x0a\x70\x75\x62\x20\x63\x6f\x6e\x73\x74\x20\x49\x74\x65\x6d\x20\x3d\x20\x73\x74\x72\x75\x63\x74\x20\x7b\x20\x69\x3a\x20\x75\x38\x20\x7d\x3b\x0a\x0a\x63\x6f\x6e\x73\x74\x20\x70\x61\x67\x65\x5f\x69\x74\x65\x6d\x73\x20\x3d\x20\x5b\x5f\x5d\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x49\x74\x65\x6d\x7b\x0a\x20\x20\x20\x20\x26\x2e\x7b\x20\x2e\x7b\x20\x2e\x69\x20\x3d\x20\x30\x20\x7d\x2c\x20\x2e\x7b\x20\x2e\x69\x20\x3d\x20\x31\x20\x7d\x2c\x20\x2e\x7b\x20\x2e\x69\x20\x3d\x20\x32\x20\x7d\x20\x7d\x2c\x0a\x20\x20\x20\x20\x26\x2e\x7b\x2e\x7b\x20\x2e\x69\x20\x3d\x20\x30\x20\x7d\x7d\x2c\x0a\x7d\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x70\x61\x67\x65\x5f\x6e\x61\x6d\x65\x73\x20\x3d\x20\x5b\x5f\x5d\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x7b\x0a\x20\x20\x20\x20\x26\x2e\x7b\x20\x22\x61\x30\x22\x2c\x20\x22\x61\x31\x22\x2c\x20\x22\x61\x32\x22\x20\x7d\x2c\x0a\x20\x20\x20\x20\x26\x2e\x7b\x22\x62\x30\x22\x7d\x2c\x0a\x7d\x3b\x0a\x0a\x2f\x2f\x2f\x20\x43\x6f\x75\x6e\x74\x73\x20\x72\x65\x61\x64\x73\x20\x74\x68\x61\x74\x20\x77\x6f\x75\x6c\x64\x20\x68\x61\x76\x65\x20\x69\x6e\x64\x65\x78\x65\x64\x20\x70\x61\x73\x74\x20\x74\x68\x65\x20\x65\x6e\x64\x20\x28\x74\x68\x65\x20\x64\x6f\x77\x6e\x73\x74\x72\x65\x61\x6d\x20\x63\x6f\x64\x65\x20\x70\x61\x6e\x69\x63\x73\x20\x74\x68\x65\x72\x65\x29\x2e\x0a\x70\x75\x62\x20\x76\x61\x72\x20\x73\x74\x61\x6c\x65\x5f\x72\x65\x61\x64\x73\x3a\x20\x75\x33\x32\x20\x3d\x20\x30\x3b\x0a\x0a\x66\x6e\x20\x69\x74\x65\x6d\x73\x28\x76\x6d\x3a\x20\x2a\x56\x6d\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x49\x74\x65\x6d\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x70\x61\x67\x65\x5f\x69\x74\x65\x6d\x73\x5b\x76\x6d\x2e\x70\x61\x67\x65\x2e\x67\x65\x74\x28\x29\x5d\x3b\x0a\x7d\x0a\x66\x6e\x20\x6e\x61\x6d\x65\x28\x76\x6d\x3a\x20\x2a\x56\x6d\x2c\x20\x69\x3a\x20\x75\x38\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x6e\x61\x6d\x65\x73\x20\x3d\x20\x70\x61\x67\x65\x5f\x6e\x61\x6d\x65\x73\x5b\x76\x6d\x2e\x70\x61\x67\x65\x2e\x67\x65\x74\x28\x29\x5d\x3b\x0a\x20\x20\x20\x20\x69\x66\x20\x28\x69\x20\x3e\x3d\x20\x6e\x61\x6d\x65\x73\x2e\x6c\x65\x6e\x29\x20\x7b\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x73\x74\x61\x6c\x65\x5f\x72\x65\x61\x64\x73\x20\x2b\x3d\x20\x31\x3b\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x22\x73\x74\x61\x6c\x65\x22\x3b\x0a\x20\x20\x20\x20\x7d\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x6e\x61\x6d\x65\x73\x5b\x69\x5d\x3b\x0a\x7d\x0a\x66\x6e\x20\x70\x69\x63\x6b\x65\x64\x28\x76\x6d\x3a\x20\x2a\x56\x6d\x29\x20\x62\x6f\x6f\x6c\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x70\x69\x63\x6b\x2e\x67\x65\x74\x28\x29\x20\x21\x3d\x20\x6e\x75\x6c\x6c\x3b\x0a\x7d\x0a\x66\x6e\x20\x70\x69\x63\x6b\x65\x64\x4e\x61\x6d\x65\x28\x76\x6d\x3a\x20\x2a\x56\x6d\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x69\x20\x3d\x20\x76\x6d\x2e\x70\x69\x63\x6b\x2e\x67\x65\x74\x28\x29\x20\x6f\x72\x65\x6c\x73\x65\x20\x7b\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x73\x74\x61\x6c\x65\x5f\x72\x65\x61\x64\x73\x20\x2b\x3d\x20\x31\x3b\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x22\x73\x74\x61\x6c\x65\x22\x3b\x0a\x20\x20\x20\x20\x7d\x3b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x70\x61\x67\x65\x5f\x6e\x61\x6d\x65\x73\x5b\x30\x5d\x5b\x69\x5d\x3b\x0a\x7d\x0a\x66\x6e\x20\x74\x61\x62\x28\x76\x6d\x3a\x20\x2a\x56\x6d\x29\x20\x54\x61\x62\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x74\x61\x62\x2e\x67\x65\x74\x28\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x66\x69\x72\x73\x74\x4e\x61\x6d\x65\x28\x76\x6d\x3a\x20\x2a\x56\x6d\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x69\x66\x20\x28\x76\x6d\x2e\x74\x61\x62\x2e\x67\x65\x74\x28\x29\x20\x21\x3d\x20\x2e\x6c\x69\x73\x74\x29\x20\x7b\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x73\x74\x61\x6c\x65\x5f\x72\x65\x61\x64\x73\x20\x2b\x3d\x20\x31\x3b\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x22\x73\x74\x61\x6c\x65\x22\x3b\x0a\x20\x20\x20\x20\x7d\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x70\x61\x67\x65\x5f\x6e\x61\x6d\x65\x73\x5b\x30\x5d\x5b\x30\x5d\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\x54\x68\x65\x20\x72\x6f\x77\x20\x77\x72\x69\x74\x74\x65\x6e\x20\x69\x6e\x6c\x69\x6e\x65\x20\x69\x6e\x20\x7b\x66\x6f\x72\x7d\x3a\x20\x69\x74\x73\x20\x74\x65\x78\x74\x20\x72\x65\x61\x64\x73\x20\x74\x68\x65\x20\x70\x61\x67\x65\x20\x73\x69\x67\x6e\x61\x6c\x20\x61\x6e\x64\x20\x74\x68\x65\x20\x72\x6f\x77\x20\x76\x61\x72\x69\x61\x62\x6c\x65\x2e\x0a\x70\x75\x62\x20\x66\x6e\x20\x49\x6e\x6c\x69\x6e\x65\x52\x6f\x77\x73\x28\x76\x6d\x3a\x20\x2a\x56\x6d\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x7b\x66\x6f\x72\x20\x28\x69\x74\x65\x6d\x73\x28\x76\x6d\x29\x29\x20\x7c\x72\x6f\x77\x7c\x20\x3c\x74\x65\x78\x74\x20\x6b\x65\x79\x3d\x7b\x72\x6f\x77\x2e\x69\x7d\x3e\x7b\x6e\x61\x6d\x65\x28\x76\x6d\x2c\x20\x72\x6f\x77\x2e\x69\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x7d\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x66\x6e\x20\x52\x6f\x77\x28\x76\x6d\x3a\x20\x2a\x56\x6d\x2c\x20\x69\x3a\x20\x75\x38\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x3c\x74\x65\x78\x74\x3e\x7b\x6e\x61\x6d\x65\x28\x76\x6d\x2c\x20\x69\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\x54\x68\x65\x20\x73\x61\x6d\x65\x20\x72\x6f\x77\x20\x61\x73\x20\x61\x20\x72\x6f\x77\x20\x63\x6f\x6d\x70\x6f\x6e\x65\x6e\x74\x2e\x0a\x70\x75\x62\x20\x66\x6e\x20\x43\x6f\x6d\x70\x6f\x6e\x65\x6e\x74\x52\x6f\x77\x73\x28\x76\x6d\x3a\x20\x2a\x56\x6d\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x7b\x66\x6f\x72\x20\x28\x69\x74\x65\x6d\x73\x28\x76\x6d\x29\x29\x20\x7c\x72\x6f\x77\x7c\x20\x3c\x52\x6f\x77\x20\x6b\x65\x79\x3d\x7b\x72\x6f\x77\x2e\x69\x7d\x20\x76\x6d\x3d\x7b\x76\x6d\x7d\x20\x69\x3d\x7b\x72\x6f\x77\x2e\x69\x7d\x20\x2f\x3e\x7d\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\x41\x20\x72\x6f\x77\x20\x69\x6e\x73\x69\x64\x65\x20\x61\x20\x72\x6f\x77\x3a\x20\x74\x68\x65\x20\x69\x6e\x6e\x65\x72\x20\x6c\x69\x73\x74\x20\x61\x6e\x64\x20\x74\x68\x65\x20\x69\x6e\x6e\x65\x72\x20\x74\x65\x78\x74\x20\x62\x6f\x74\x68\x20\x72\x65\x61\x64\x20\x74\x68\x65\x20\x70\x61\x67\x65\x20\x73\x69\x67\x6e\x61\x6c\x2e\x0a\x70\x75\x62\x20\x66\x6e\x20\x4e\x65\x73\x74\x65\x64\x52\x6f\x77\x73\x28\x76\x6d\x3a\x20\x2a\x56\x6d\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x7b\x66\x6f\x72\x20\x28\x69\x74\x65\x6d\x73\x28\x76\x6d\x29\x29\x20\x7c\x72\x6f\x77\x7c\x20\x3c\x63\x6f\x6c\x20\x6b\x65\x79\x3d\x7b\x72\x6f\x77\x2e\x69\x7d\x3e\x7b\x66\x6f\x72\x20\x28\x69\x74\x65\x6d\x73\x28\x76\x6d\x29\x29\x20\x7c\x63\x65\x6c\x6c\x7c\x20\x3c\x74\x65\x78\x74\x20\x6b\x65\x79\x3d\x7b\x63\x65\x6c\x6c\x2e\x69\x7d\x3e\x7b\x6e\x61\x6d\x65\x28\x76\x6d\x2c\x20\x63\x65\x6c\x6c\x2e\x69\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x7d\x3c\x2f\x63\x6f\x6c\x3e\x7d\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\x41\x6e\x20\x7b\x69\x66\x7d\x20\x62\x72\x61\x6e\x63\x68\x20\x77\x68\x6f\x73\x65\x20\x74\x65\x78\x74\x20\x72\x65\x61\x64\x73\x20\x74\x68\x65\x20\x63\x6f\x6e\x64\x69\x74\x69\x6f\x6e\x27\x73\x20\x73\x69\x67\x6e\x61\x6c\x2e\x0a\x70\x75\x62\x20\x66\x6e\x20\x50\x69\x63\x6b\x65\x64\x28\x76\x6d\x3a\x20\x2a\x56\x6d\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x7b\x69\x66\x20\x28\x70\x69\x63\x6b\x65\x64\x28\x76\x6d\x29\x29\x20\x3c\x74\x65\x78\x74\x3e\x7b\x70\x69\x63\x6b\x65\x64\x4e\x61\x6d\x65\x28\x76\x6d\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x20\x65\x6c\x73\x65\x20\x3c\x74\x65\x78\x74\x3e\x6e\x6f\x6e\x65\x3c\x2f\x74\x65\x78\x74\x3e\x7d\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\x41\x20\x7b\x73\x77\x69\x74\x63\x68\x7d\x20\x62\x72\x61\x6e\x63\x68\x20\x77\x68\x6f\x73\x65\x20\x74\x65\x78\x74\x20\x72\x65\x61\x64\x73\x20\x74\x68\x65\x20\x73\x77\x69\x74\x63\x68\x65\x64\x20\x73\x69\x67\x6e\x61\x6c\x2e\x0a\x70\x75\x62\x20\x66\x6e\x20\x54\x61\x62\x73\x28\x76\x6d\x3a\x20\x2a\x56\x6d\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x7b\x73\x77\x69\x74\x63\x68\x20\x28\x74\x61\x62\x28\x76\x6d\x29\x29\x20\x7b\x20\x2e\x6c\x69\x73\x74\x20\x3d\x3e\x20\x3c\x74\x65\x78\x74\x3e\x7b\x66\x69\x72\x73\x74\x4e\x61\x6d\x65\x28\x76\x6d\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x2c\x20\x2e\x65\x6d\x70\x74\x79\x20\x3d\x3e\x20\x3c\x74\x65\x78\x74\x3e\x65\x6d\x70\x74\x79\x3c\x2f\x74\x65\x78\x74\x3e\x20\x7d\x7d\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a" else null;
const __YixStyleCatalog = if (ui.view.template.preview_enabled) ui.view.template.styleCatalog(.{ .@"page_items " = page_items, .@"page_names " = page_names, }) else void;

//# yix-map-data [[1761,1761],[5364,1922],[7657,2037],[11224,2285],[16408,2560],[20107,2785]]

//# yix-map subtree_order.yix
