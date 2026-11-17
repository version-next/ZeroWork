// GENERATED FILE, do not edit: generated from overview.yix; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! 分类概览（Pencil `WswfJ`）：hero（`HiaCV`）与每个子页面一行（`IhVlT` / `sxDUF`）。
//! 行是 `W.Pressable`（行 test_id 在可点击根上、摘要 test_id 在承载文字的节点上）；摘要随草稿由选择器驱动。
const ui = @import("ui");
const W = ui.widgets;
const m = @import("../model/view_model.zig");
const S = @import("_styles.yss.zig");
const subpages = @import("settings_subpages.zig");
fn send(vm: *m.ViewModel, intent: m.Intent) void {
    vm.dispatch(intent);
}
fn heroIcon(vm: *m.ViewModel) ui.SvgAsset {
    return subpages.iconAsset(subpages.categories[vm.pageIndex()].icon);
}
fn heroTitle(vm: *m.ViewModel) []const u8 {
    return m.catalog.title(vm.pageIndex());
}
fn heroText(vm: *m.ViewModel) []const u8 {
    return subpages.categories[vm.pageIndex()].description;
}
/// 当前分类的子页面行；行内派生直接读当前分类（`vm.pageIndex()`），见 `m.OverviewItem`。
fn rows(vm: *m.ViewModel) []const m.OverviewItem {
    return vm.overviewItems();
}
fn subTitle(vm: *m.ViewModel, sub: u8) []const u8 {
    const page = vm.pageIndex();
    return subpages.categories[page].subpages[sub].title;
}
fn subIcon(vm: *m.ViewModel, sub: u8) ui.SvgAsset {
    const page = vm.pageIndex();
    return subpages.iconAsset(subpages.categories[page].subpages[sub].icon);
}
fn rowId(vm: *m.ViewModel, sub: u8) []const u8 {
    const page = vm.pageIndex();
    return m.ids.overviewRow(page, sub).?.row;
}
fn summaryId(vm: *m.ViewModel, sub: u8) []const u8 {
    const page = vm.pageIndex();
    return m.ids.overviewRow(page, sub).?.summary;
}
fn summary(vm: *m.ViewModel, sub: u8) []const u8 {
    return vm.overviewSummary(sub);
}
fn locked(vm: *m.ViewModel) bool {
    return vm.controlsLocked();
}

pub fn Overview(args: anytype) ui.view.ComponentOf(__yix_Overview) {
    return ui.view.component(__yix_Overview, ui.reactive.props.coerce(OverviewProps, args));
}
pub const OverviewProps = struct {
    vm: ui.Source(*m.ViewModel),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = Overview;
    pub const __yix_preview_mount = __yix_Overview;
};
fn __yix_Overview(__yix_props: OverviewProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/settings/view/overview.yix", .path = "Overview", .receiver = "box", .tokens = "box testId = @static; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"settings.overview\" ", .kind = .property, .literal = .{ .text = "settings.overview" } }, .{ .name = "style", .tokens = "S . overview_root ", .kind = .style, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .vm = __yix_view_ctx.vm, }, ui.view.box(.{ .test_id = "settings.overview", .style = S.overview_root, }, .{
            ui.view.templateSite(.{ .module = "src/features/settings/view/overview.yix", .path = "Overview", .receiver = "box", .tokens = "box testId = @static; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"settings.overview.hero\" ", .kind = .property, .literal = .{ .text = "settings.overview.hero" } }, .{ .name = "style", .tokens = "S . hero ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.box(.{ .test_id = "settings.overview.hero", .style = S.hero, }, .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/overview.yix", .path = "Overview", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . hero_tile ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.box(.{ .style = S.hero_tile, }, .{
                    ui.view.templateSite(.{ .module = "src/features/settings/view/overview.yix", .path = "Overview", .receiver = "icon", .tokens = "icon src = heroIcon ( vm ) ; style = . { S . hero_icon , S . hero_icon_ink } ; ", .literal_text = null, .attributes = &.{ .{ .name = "src", .tokens = "heroIcon ( vm ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = ". { S . hero_icon , S . hero_icon_ink } ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.icon(.{ .style = .{ S.hero_icon, S.hero_icon_ink }, }, __yix_d1: {
        const __yix_T = @TypeOf(heroIcon(__yix_view_ctx.vm.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return heroIcon(__yix_ctx.vm.get());
        } }.__yix_compute);
    })),
                })),
                ui.view.templateSite(.{ .module = "src/features/settings/view/overview.yix", .path = "Overview", .receiver = "text", .tokens = "text style = @static; heroTitle ( vm )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . hero_title ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.text(.{ .style = S.hero_title, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d2: {
        const __yix_T = @TypeOf(heroTitle(__yix_view_ctx.vm.peek()));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return heroTitle(__yix_ctx.vm.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d2: {
        const __yix_T = @TypeOf(heroTitle(__yix_view_ctx.vm.peek()));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return heroTitle(__yix_ctx.vm.get());
        } }.__yix_compute);
    }, }))),
                ui.view.templateSite(.{ .module = "src/features/settings/view/overview.yix", .path = "Overview", .receiver = "text", .tokens = "text style = @static; box = S . hero_description_box ; heroText ( vm )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . hero_text ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . hero_description_box ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.text(.{ .style = S.hero_text, .box = S.hero_description_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d3: {
        const __yix_T = @TypeOf(heroText(__yix_view_ctx.vm.peek()));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return heroText(__yix_ctx.vm.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d3: {
        const __yix_T = @TypeOf(heroText(__yix_view_ctx.vm.peek()));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return heroText(__yix_ctx.vm.get());
        } }.__yix_compute);
    }, }))),
            })),
            ui.view.templateSite(.{ .module = "src/features/settings/view/overview.yix", .path = "Overview", .receiver = "box", .tokens = "box testId = @static; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"settings.overview.list\" ", .kind = .property, .literal = .{ .text = "settings.overview.list" } }, .{ .name = "style", .tokens = "S . overview_list ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.box(.{ .test_id = "settings.overview.list", .style = S.overview_list, }, .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/overview.yix", .path = "Overview", .receiver = "control", .tokens = "for ( rows ( vm ) ) | row | < W . Pressable key = { row . key } testId = { rowId ( vm , row . sub ) } a11yLabel = { subTitle ( vm , row . sub ) } disabled = { locked ( vm ) } onClick = { send ( vm , m . Intent . openSubpage ( row . sub ) ) } style = { S . OverviewRow . of ( . { . locked = locked ( vm ) } ) } > < box style = { S . overview_tile } > < icon src = { subIcon ( vm , row . sub ) } style = { S . overview_tile_icon } / > < / box > < box style = { S . OverviewInner . of ( . { . last = row . last } ) } > < box style = { S . overview_copy } > < text style = { S . overview_label } > { subTitle ( vm , row . sub ) } < / text > < text testId = { summaryId ( vm , row . sub ) } style = { S . overview_summary } box = { S . overview_summary_box } > { summary ( vm , row . sub ) } < / text > < / box > < icon src = { ui . icons . chevron_right } style = { S . overview_chevron } / > < / box > < / W . Pressable > " }, .{ .vm = __yix_view_ctx.vm, }, __yix_e1: { const __yix_items_1 = __yix_d11: {
        const __yix_T = @TypeOf(rows(__yix_view_ctx.vm.peek()));
        break :__yix_d11 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return rows(__yix_ctx.vm.get());
        } }.__yix_compute);
    }; break :__yix_e1 ui.view.eachWith(.{ .vm = __yix_view_ctx.vm, }, __yix_items_1, struct { fn __yix_k(row: ui.view.yixItem(@TypeOf(__yix_items_1))) u64 { return ui.view.keyOf(row.key); } }.__yix_k, struct { fn __yix_row(__yix_row_1: anytype, row: ui.Source(ui.view.yixItem(@TypeOf(__yix_items_1))), __yix_scope_1: *ui.Scope, __yix_cx_1: *ui.Cx) anyerror!*ui.Node { return ui.view.render(__yix_scope_1, __yix_cx_1, ui.view.templateSite(.{ .module = "src/features/settings/view/overview.yix", .path = "Overview/keyword_for:1", .receiver = "W.Pressable", .tokens = "< W . Pressable key = { row . key } testId = { rowId ( vm , row . sub ) } a11yLabel = { subTitle ( vm , row . sub ) } disabled = { locked ( vm ) } onClick = { send ( vm , m . Intent . openSubpage ( row . sub ) ) } style = { S . OverviewRow . of ( . { . locked = locked ( vm ) } ) } > < box style = { S . overview_tile } > < icon src = { subIcon ( vm , row . sub ) } style = { S . overview_tile_icon } / > < / box > < box style = { S . OverviewInner . of ( . { . last = row . last } ) } > < box style = { S . overview_copy } > < text style = { S . overview_label } > { subTitle ( vm , row . sub ) } < / text > < text testId = { summaryId ( vm , row . sub ) } style = { S . overview_summary } box = { S . overview_summary_box } > { summary ( vm , row . sub ) } < / text > < / box > < icon src = { ui . icons . chevron_right } style = { S . overview_chevron } / > < / box > < / W . Pressable > ", .literal_text = null, .attributes = &.{ .{ .name = "key", .tokens = "row . key ", .kind = .property, .literal = null }, .{ .name = "test_id", .tokens = "rowId ( vm , row . sub ) ", .kind = .property, .literal = null }, .{ .name = "a11y_label", .tokens = "subTitle ( vm , row . sub ) ", .kind = .property, .literal = null }, .{ .name = "disabled", .tokens = "locked ( vm ) ", .kind = .property, .literal = null }, .{ .name = "on_click", .tokens = "send ( vm , m . Intent . openSubpage ( row . sub ) ) ", .kind = .event, .literal = null }, .{ .name = "style", .tokens = "S . OverviewRow . of ( . { . locked = locked ( vm ) } ) ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_row_1.vm, .row = row, }, ui.view.templateAttrs(.{ .test_id = __yix_d1: {
        const __yix_T = if (ui.view.attrType(W.Pressable, "test_id")) |__yix_A| __yix_A else @TypeOf(rowId(__yix_row_1.vm.peek(), row.peek().sub));
        break :__yix_d1 try __yix_scope_1.derive(__yix_T, .{ .vm = __yix_row_1.vm, .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return rowId(__yix_ctx.vm.get(), __yix_ctx.row.get().sub);
        } }.__yix_compute);
    }, .style = S.OverviewRow.of(.{ .locked = __yix_d5: {
        const __yix_T = @TypeOf(locked(__yix_row_1.vm.peek()));
        break :__yix_d5 try __yix_scope_1.derive(__yix_T, .{ .vm = __yix_row_1.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return locked(__yix_ctx.vm.get());
        } }.__yix_compute);
    } }), }, __yix_builder_21: { try ui.view.previewCheckBuilder(__yix_scope_1, W.Pressable); break :__yix_builder_21 ui.view.with(W.Pressable(.{ .a11y_label = __yix_d2: {
        const __yix_T = if (ui.view.attrType(W.Pressable, "a11y_label")) |__yix_A| __yix_A else @TypeOf(subTitle(__yix_row_1.vm.peek(), row.peek().sub));
        break :__yix_d2 try __yix_scope_1.derive(__yix_T, .{ .vm = __yix_row_1.vm, .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return subTitle(__yix_ctx.vm.get(), __yix_ctx.row.get().sub);
        } }.__yix_compute);
    }, .disabled = __yix_d3: {
        const __yix_T = if (ui.view.attrType(W.Pressable, "disabled")) |__yix_A| __yix_A else @TypeOf(locked(__yix_row_1.vm.peek()));
        break :__yix_d3 try __yix_scope_1.derive(__yix_T, .{ .vm = __yix_row_1.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return locked(__yix_ctx.vm.get());
        } }.__yix_compute);
    }, .on_click = if (comptime ui.view.isEventProp(W.Pressable, "on_click")) try ui.on.bindAny(__yix_scope_1, .{ .vm = __yix_row_1.vm, .row = row, .__yix_owner = __yix_scope_1.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); send(__yix_ctx.vm.peek(), m.Intent.openSubpage(__yix_ctx.row.peek().sub));  } }.__yix_run) else __yix_d4: {
        const __yix_T = if (ui.view.attrType(W.Pressable, "on_click")) |__yix_A| __yix_A else @TypeOf(send(__yix_row_1.vm.peek(), m.Intent.openSubpage(row.peek().sub)));
        break :__yix_d4 try __yix_scope_1.derive(__yix_T, .{ .vm = __yix_row_1.vm, .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return send(__yix_ctx.vm.get(), m.Intent.openSubpage(__yix_ctx.row.get().sub));
        } }.__yix_compute);
    }, }), .{
                        ui.view.templateSite(.{ .module = "src/features/settings/view/overview.yix", .path = "Overview/keyword_for:1", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . overview_tile ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_row_1.vm, .row = row, }, ui.view.box(.{ .style = S.overview_tile, }, .{
                            ui.view.templateSite(.{ .module = "src/features/settings/view/overview.yix", .path = "Overview/keyword_for:1", .receiver = "icon", .tokens = "icon src = subIcon ( vm , row . sub ) ; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "src", .tokens = "subIcon ( vm , row . sub ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . overview_tile_icon ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_row_1.vm, .row = row, }, ui.view.icon(.{ .style = S.overview_tile_icon, }, __yix_d6: {
        const __yix_T = @TypeOf(subIcon(__yix_row_1.vm.peek(), row.peek().sub));
        break :__yix_d6 try __yix_scope_1.derive(__yix_T, .{ .vm = __yix_row_1.vm, .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return subIcon(__yix_ctx.vm.get(), __yix_ctx.row.get().sub);
        } }.__yix_compute);
    })),
                        })),
                        ui.view.templateSite(.{ .module = "src/features/settings/view/overview.yix", .path = "Overview/keyword_for:1", .receiver = "box", .tokens = "box style = S . OverviewInner . of ( . { . last = row . last } ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . OverviewInner . of ( . { . last = row . last } ) ", .kind = .style, .literal = null }, } }, .{ .row = row, .vm = __yix_row_1.vm, }, ui.view.box(.{ .style = S.OverviewInner.of(.{ .last = __yix_d7: {
        const __yix_T = @TypeOf(row.peek().last);
        break :__yix_d7 try __yix_scope_1.derive(__yix_T, .{ .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.row.get().last;
        } }.__yix_compute);
    } }), }, .{
                            ui.view.templateSite(.{ .module = "src/features/settings/view/overview.yix", .path = "Overview/keyword_for:1", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . overview_copy ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_row_1.vm, .row = row, }, ui.view.box(.{ .style = S.overview_copy, }, .{
                                ui.view.templateSite(.{ .module = "src/features/settings/view/overview.yix", .path = "Overview/keyword_for:1", .receiver = "text", .tokens = "text style = @static; subTitle ( vm , row . sub )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . overview_label ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_row_1.vm, .row = row, }, ui.view.text(.{ .style = S.overview_label, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d8: {
        const __yix_T = @TypeOf(subTitle(__yix_row_1.vm.peek(), row.peek().sub));
        break :__yix_d8 try __yix_scope_1.derive(__yix_T, .{ .vm = __yix_row_1.vm, .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return subTitle(__yix_ctx.vm.get(), __yix_ctx.row.get().sub);
        } }.__yix_compute);
    }), ""), .{ __yix_d8: {
        const __yix_T = @TypeOf(subTitle(__yix_row_1.vm.peek(), row.peek().sub));
        break :__yix_d8 try __yix_scope_1.derive(__yix_T, .{ .vm = __yix_row_1.vm, .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return subTitle(__yix_ctx.vm.get(), __yix_ctx.row.get().sub);
        } }.__yix_compute);
    }, }))),
                                ui.view.templateSite(.{ .module = "src/features/settings/view/overview.yix", .path = "Overview/keyword_for:1", .receiver = "text", .tokens = "text testId = summaryId ( vm , row . sub ) ; style = @static; box = S . overview_summary_box ; summary ( vm , row . sub )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "summaryId ( vm , row . sub ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . overview_summary ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . overview_summary_box ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_row_1.vm, .row = row, }, ui.view.text(.{ .test_id = __yix_d9: {
        const __yix_T = @TypeOf(summaryId(__yix_row_1.vm.peek(), row.peek().sub));
        break :__yix_d9 try __yix_scope_1.derive(__yix_T, .{ .vm = __yix_row_1.vm, .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return summaryId(__yix_ctx.vm.get(), __yix_ctx.row.get().sub);
        } }.__yix_compute);
    }, .style = S.overview_summary, .box = S.overview_summary_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d10: {
        const __yix_T = @TypeOf(summary(__yix_row_1.vm.peek(), row.peek().sub));
        break :__yix_d10 try __yix_scope_1.derive(__yix_T, .{ .vm = __yix_row_1.vm, .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return summary(__yix_ctx.vm.get(), __yix_ctx.row.get().sub);
        } }.__yix_compute);
    }), ""), .{ __yix_d10: {
        const __yix_T = @TypeOf(summary(__yix_row_1.vm.peek(), row.peek().sub));
        break :__yix_d10 try __yix_scope_1.derive(__yix_T, .{ .vm = __yix_row_1.vm, .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return summary(__yix_ctx.vm.get(), __yix_ctx.row.get().sub);
        } }.__yix_compute);
    }, }))),
                            })),
                            ui.view.templateSite(.{ .module = "src/features/settings/view/overview.yix", .path = "Overview/keyword_for:1", .receiver = "icon", .tokens = "icon src = ui . icons . chevron_right ; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "src", .tokens = "ui . icons . chevron_right ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . overview_chevron ", .kind = .style, .literal = null }, } }, .{ }, ui.view.icon(.{ .style = S.overview_chevron, }, ui.icons.chevron_right)),
                        })),
                    }); }))); } }.__yix_row); }),
            })),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "Overview";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

const __yix_preview_source: ?[]const u8 = if (ui.view.template.preview_enabled) "\x2f\x2f\x21\x20\xe5\x88\x86\xe7\xb1\xbb\xe6\xa6\x82\xe8\xa7\x88\xef\xbc\x88\x50\x65\x6e\x63\x69\x6c\x20\x60\x57\x73\x77\x66\x4a\x60\xef\xbc\x89\xef\xbc\x9a\x68\x65\x72\x6f\xef\xbc\x88\x60\x48\x69\x61\x43\x56\x60\xef\xbc\x89\xe4\xb8\x8e\xe6\xaf\x8f\xe4\xb8\xaa\xe5\xad\x90\xe9\xa1\xb5\xe9\x9d\xa2\xe4\xb8\x80\xe8\xa1\x8c\xef\xbc\x88\x60\x49\x68\x56\x6c\x54\x60\x20\x2f\x20\x60\x73\x78\x44\x55\x46\x60\xef\xbc\x89\xe3\x80\x82\x0a\x2f\x2f\x21\x20\xe8\xa1\x8c\xe6\x98\xaf\x20\x60\x57\x2e\x50\x72\x65\x73\x73\x61\x62\x6c\x65\x60\xef\xbc\x88\xe8\xa1\x8c\x20\x74\x65\x73\x74\x5f\x69\x64\x20\xe5\x9c\xa8\xe5\x8f\xaf\xe7\x82\xb9\xe5\x87\xbb\xe6\xa0\xb9\xe4\xb8\x8a\xe3\x80\x81\xe6\x91\x98\xe8\xa6\x81\x20\x74\x65\x73\x74\x5f\x69\x64\x20\xe5\x9c\xa8\xe6\x89\xbf\xe8\xbd\xbd\xe6\x96\x87\xe5\xad\x97\xe7\x9a\x84\xe8\x8a\x82\xe7\x82\xb9\xe4\xb8\x8a\xef\xbc\x89\xef\xbc\x9b\xe6\x91\x98\xe8\xa6\x81\xe9\x9a\x8f\xe8\x8d\x89\xe7\xa8\xbf\xe7\x94\xb1\xe9\x80\x89\xe6\x8b\xa9\xe5\x99\xa8\xe9\xa9\xb1\xe5\x8a\xa8\xe3\x80\x82\x0a\x63\x6f\x6e\x73\x74\x20\x75\x69\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x75\x69\x22\x29\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x57\x20\x3d\x20\x75\x69\x2e\x77\x69\x64\x67\x65\x74\x73\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x6d\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x2e\x2e\x2f\x6d\x6f\x64\x65\x6c\x2f\x76\x69\x65\x77\x5f\x6d\x6f\x64\x65\x6c\x2e\x7a\x69\x67\x22\x29\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x53\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x73\x74\x79\x6c\x65\x73\x2e\x79\x73\x73\x22\x29\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x73\x75\x62\x70\x61\x67\x65\x73\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x73\x65\x74\x74\x69\x6e\x67\x73\x5f\x73\x75\x62\x70\x61\x67\x65\x73\x2e\x7a\x69\x67\x22\x29\x3b\x0a\x66\x6e\x20\x73\x65\x6e\x64\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x69\x6e\x74\x65\x6e\x74\x3a\x20\x6d\x2e\x49\x6e\x74\x65\x6e\x74\x29\x20\x76\x6f\x69\x64\x20\x7b\x0a\x20\x20\x20\x20\x76\x6d\x2e\x64\x69\x73\x70\x61\x74\x63\x68\x28\x69\x6e\x74\x65\x6e\x74\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x68\x65\x72\x6f\x49\x63\x6f\x6e\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x29\x20\x75\x69\x2e\x53\x76\x67\x41\x73\x73\x65\x74\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x73\x75\x62\x70\x61\x67\x65\x73\x2e\x69\x63\x6f\x6e\x41\x73\x73\x65\x74\x28\x73\x75\x62\x70\x61\x67\x65\x73\x2e\x63\x61\x74\x65\x67\x6f\x72\x69\x65\x73\x5b\x76\x6d\x2e\x70\x61\x67\x65\x49\x6e\x64\x65\x78\x28\x29\x5d\x2e\x69\x63\x6f\x6e\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x68\x65\x72\x6f\x54\x69\x74\x6c\x65\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x6d\x2e\x63\x61\x74\x61\x6c\x6f\x67\x2e\x74\x69\x74\x6c\x65\x28\x76\x6d\x2e\x70\x61\x67\x65\x49\x6e\x64\x65\x78\x28\x29\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x68\x65\x72\x6f\x54\x65\x78\x74\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x73\x75\x62\x70\x61\x67\x65\x73\x2e\x63\x61\x74\x65\x67\x6f\x72\x69\x65\x73\x5b\x76\x6d\x2e\x70\x61\x67\x65\x49\x6e\x64\x65\x78\x28\x29\x5d\x2e\x64\x65\x73\x63\x72\x69\x70\x74\x69\x6f\x6e\x3b\x0a\x7d\x0a\x2f\x2f\x2f\x20\xe5\xbd\x93\xe5\x89\x8d\xe5\x88\x86\xe7\xb1\xbb\xe7\x9a\x84\xe5\xad\x90\xe9\xa1\xb5\xe9\x9d\xa2\xe8\xa1\x8c\xef\xbc\x9b\xe8\xa1\x8c\xe5\x86\x85\xe6\xb4\xbe\xe7\x94\x9f\xe7\x9b\xb4\xe6\x8e\xa5\xe8\xaf\xbb\xe5\xbd\x93\xe5\x89\x8d\xe5\x88\x86\xe7\xb1\xbb\xef\xbc\x88\x60\x76\x6d\x2e\x70\x61\x67\x65\x49\x6e\x64\x65\x78\x28\x29\x60\xef\xbc\x89\xef\xbc\x8c\xe8\xa7\x81\x20\x60\x6d\x2e\x4f\x76\x65\x72\x76\x69\x65\x77\x49\x74\x65\x6d\x60\xe3\x80\x82\x0a\x66\x6e\x20\x72\x6f\x77\x73\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x6d\x2e\x4f\x76\x65\x72\x76\x69\x65\x77\x49\x74\x65\x6d\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x6f\x76\x65\x72\x76\x69\x65\x77\x49\x74\x65\x6d\x73\x28\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x73\x75\x62\x54\x69\x74\x6c\x65\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x73\x75\x62\x3a\x20\x75\x38\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x70\x61\x67\x65\x20\x3d\x20\x76\x6d\x2e\x70\x61\x67\x65\x49\x6e\x64\x65\x78\x28\x29\x3b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x73\x75\x62\x70\x61\x67\x65\x73\x2e\x63\x61\x74\x65\x67\x6f\x72\x69\x65\x73\x5b\x70\x61\x67\x65\x5d\x2e\x73\x75\x62\x70\x61\x67\x65\x73\x5b\x73\x75\x62\x5d\x2e\x74\x69\x74\x6c\x65\x3b\x0a\x7d\x0a\x66\x6e\x20\x73\x75\x62\x49\x63\x6f\x6e\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x73\x75\x62\x3a\x20\x75\x38\x29\x20\x75\x69\x2e\x53\x76\x67\x41\x73\x73\x65\x74\x20\x7b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x70\x61\x67\x65\x20\x3d\x20\x76\x6d\x2e\x70\x61\x67\x65\x49\x6e\x64\x65\x78\x28\x29\x3b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x73\x75\x62\x70\x61\x67\x65\x73\x2e\x69\x63\x6f\x6e\x41\x73\x73\x65\x74\x28\x73\x75\x62\x70\x61\x67\x65\x73\x2e\x63\x61\x74\x65\x67\x6f\x72\x69\x65\x73\x5b\x70\x61\x67\x65\x5d\x2e\x73\x75\x62\x70\x61\x67\x65\x73\x5b\x73\x75\x62\x5d\x2e\x69\x63\x6f\x6e\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x72\x6f\x77\x49\x64\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x73\x75\x62\x3a\x20\x75\x38\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x70\x61\x67\x65\x20\x3d\x20\x76\x6d\x2e\x70\x61\x67\x65\x49\x6e\x64\x65\x78\x28\x29\x3b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x6d\x2e\x69\x64\x73\x2e\x6f\x76\x65\x72\x76\x69\x65\x77\x52\x6f\x77\x28\x70\x61\x67\x65\x2c\x20\x73\x75\x62\x29\x2e\x3f\x2e\x72\x6f\x77\x3b\x0a\x7d\x0a\x66\x6e\x20\x73\x75\x6d\x6d\x61\x72\x79\x49\x64\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x73\x75\x62\x3a\x20\x75\x38\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x70\x61\x67\x65\x20\x3d\x20\x76\x6d\x2e\x70\x61\x67\x65\x49\x6e\x64\x65\x78\x28\x29\x3b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x6d\x2e\x69\x64\x73\x2e\x6f\x76\x65\x72\x76\x69\x65\x77\x52\x6f\x77\x28\x70\x61\x67\x65\x2c\x20\x73\x75\x62\x29\x2e\x3f\x2e\x73\x75\x6d\x6d\x61\x72\x79\x3b\x0a\x7d\x0a\x66\x6e\x20\x73\x75\x6d\x6d\x61\x72\x79\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x73\x75\x62\x3a\x20\x75\x38\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x6f\x76\x65\x72\x76\x69\x65\x77\x53\x75\x6d\x6d\x61\x72\x79\x28\x73\x75\x62\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x6c\x6f\x63\x6b\x65\x64\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x29\x20\x62\x6f\x6f\x6c\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x63\x6f\x6e\x74\x72\x6f\x6c\x73\x4c\x6f\x63\x6b\x65\x64\x28\x29\x3b\x0a\x7d\x0a\x0a\x70\x75\x62\x20\x66\x6e\x20\x4f\x76\x65\x72\x76\x69\x65\x77\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x65\x74\x74\x69\x6e\x67\x73\x2e\x6f\x76\x65\x72\x76\x69\x65\x77\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6f\x76\x65\x72\x76\x69\x65\x77\x5f\x72\x6f\x6f\x74\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x65\x74\x74\x69\x6e\x67\x73\x2e\x6f\x76\x65\x72\x76\x69\x65\x77\x2e\x68\x65\x72\x6f\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x68\x65\x72\x6f\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x68\x65\x72\x6f\x5f\x74\x69\x6c\x65\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x69\x63\x6f\x6e\x20\x73\x72\x63\x3d\x7b\x68\x65\x72\x6f\x49\x63\x6f\x6e\x28\x76\x6d\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x2e\x7b\x20\x53\x2e\x68\x65\x72\x6f\x5f\x69\x63\x6f\x6e\x2c\x20\x53\x2e\x68\x65\x72\x6f\x5f\x69\x63\x6f\x6e\x5f\x69\x6e\x6b\x20\x7d\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x68\x65\x72\x6f\x5f\x74\x69\x74\x6c\x65\x7d\x3e\x7b\x68\x65\x72\x6f\x54\x69\x74\x6c\x65\x28\x76\x6d\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x68\x65\x72\x6f\x5f\x74\x65\x78\x74\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x68\x65\x72\x6f\x5f\x64\x65\x73\x63\x72\x69\x70\x74\x69\x6f\x6e\x5f\x62\x6f\x78\x7d\x3e\x7b\x68\x65\x72\x6f\x54\x65\x78\x74\x28\x76\x6d\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x65\x74\x74\x69\x6e\x67\x73\x2e\x6f\x76\x65\x72\x76\x69\x65\x77\x2e\x6c\x69\x73\x74\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6f\x76\x65\x72\x76\x69\x65\x77\x5f\x6c\x69\x73\x74\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x7b\x66\x6f\x72\x20\x28\x72\x6f\x77\x73\x28\x76\x6d\x29\x29\x20\x7c\x72\x6f\x77\x7c\x20\x3c\x57\x2e\x50\x72\x65\x73\x73\x61\x62\x6c\x65\x20\x6b\x65\x79\x3d\x7b\x72\x6f\x77\x2e\x6b\x65\x79\x7d\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x72\x6f\x77\x49\x64\x28\x76\x6d\x2c\x20\x72\x6f\x77\x2e\x73\x75\x62\x29\x7d\x20\x61\x31\x31\x79\x4c\x61\x62\x65\x6c\x3d\x7b\x73\x75\x62\x54\x69\x74\x6c\x65\x28\x76\x6d\x2c\x20\x72\x6f\x77\x2e\x73\x75\x62\x29\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x6c\x6f\x63\x6b\x65\x64\x28\x76\x6d\x29\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x73\x65\x6e\x64\x28\x76\x6d\x2c\x20\x6d\x2e\x49\x6e\x74\x65\x6e\x74\x2e\x6f\x70\x65\x6e\x53\x75\x62\x70\x61\x67\x65\x28\x72\x6f\x77\x2e\x73\x75\x62\x29\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x4f\x76\x65\x72\x76\x69\x65\x77\x52\x6f\x77\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x6c\x6f\x63\x6b\x65\x64\x20\x3d\x20\x6c\x6f\x63\x6b\x65\x64\x28\x76\x6d\x29\x20\x7d\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6f\x76\x65\x72\x76\x69\x65\x77\x5f\x74\x69\x6c\x65\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x69\x63\x6f\x6e\x20\x73\x72\x63\x3d\x7b\x73\x75\x62\x49\x63\x6f\x6e\x28\x76\x6d\x2c\x20\x72\x6f\x77\x2e\x73\x75\x62\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6f\x76\x65\x72\x76\x69\x65\x77\x5f\x74\x69\x6c\x65\x5f\x69\x63\x6f\x6e\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x4f\x76\x65\x72\x76\x69\x65\x77\x49\x6e\x6e\x65\x72\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x6c\x61\x73\x74\x20\x3d\x20\x72\x6f\x77\x2e\x6c\x61\x73\x74\x20\x7d\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6f\x76\x65\x72\x76\x69\x65\x77\x5f\x63\x6f\x70\x79\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6f\x76\x65\x72\x76\x69\x65\x77\x5f\x6c\x61\x62\x65\x6c\x7d\x3e\x7b\x73\x75\x62\x54\x69\x74\x6c\x65\x28\x76\x6d\x2c\x20\x72\x6f\x77\x2e\x73\x75\x62\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x73\x75\x6d\x6d\x61\x72\x79\x49\x64\x28\x76\x6d\x2c\x20\x72\x6f\x77\x2e\x73\x75\x62\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6f\x76\x65\x72\x76\x69\x65\x77\x5f\x73\x75\x6d\x6d\x61\x72\x79\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x6f\x76\x65\x72\x76\x69\x65\x77\x5f\x73\x75\x6d\x6d\x61\x72\x79\x5f\x62\x6f\x78\x7d\x3e\x7b\x73\x75\x6d\x6d\x61\x72\x79\x28\x76\x6d\x2c\x20\x72\x6f\x77\x2e\x73\x75\x62\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x69\x63\x6f\x6e\x20\x73\x72\x63\x3d\x7b\x75\x69\x2e\x69\x63\x6f\x6e\x73\x2e\x63\x68\x65\x76\x72\x6f\x6e\x5f\x72\x69\x67\x68\x74\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6f\x76\x65\x72\x76\x69\x65\x77\x5f\x63\x68\x65\x76\x72\x6f\x6e\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x50\x72\x65\x73\x73\x61\x62\x6c\x65\x3e\x7d\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a" else null;
const __YixStyleCatalog = if (ui.view.template.preview_enabled) ui.view.template.styleCatalog(.{ .@"S " = S, }) else void;

//# yix-map-data [[1769,1764]]

//# yix-map overview.yix
