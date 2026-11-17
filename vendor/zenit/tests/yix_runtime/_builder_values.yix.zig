// GENERATED FILE, do not edit: generated from builder_values.yix; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! Runtime fixture for parameters forwarded to builder widget props (ZeroWork G25): a row
//! component passes its parameters to `W.Input` / `W.Select` / `W.Tooltip` as written. Props
//! typed `ui.Source(T)` (placeholder, disabled, options, text) follow the parameter; plain-value
//! props (appendText, width, size) take the parameter's value once, when the widget is built
//! (at mount). Also the Yix components (`W.Button`, `W.Switch`, …), whose parameters are all
//! sources, and the G24 forms (`parts` test id, whole `a11y` value) over a struct parameter.
//! Lives outside tests/yix so it is not an LP3 equivalence input (those need reviewed goldens).
const ui = @import("ui");
const W = ui.widgets;

pub const Row = struct {
    unit: []const u8 = "MB",
    id: []const u8 = "row.field",
    name: []const u8 = "row",
};

fn unitOf(row: Row) []const u8 {
    return row.unit;
}

fn fieldId(row: Row) []const u8 {
    return row.id;
}

fn switchA11y(row: Row, on: bool) ?ui.A11yProps {
    return .{ .role = .switch_role, .checked = on, .label = row.name };
}

/// Parameters forwarded as written: `unit` / `width` into plain props, `hint` / `off` into sources.
pub fn InputRow(args: anytype) ui.view.ComponentOf(__yix_InputRow) {
    return ui.view.component(__yix_InputRow, ui.reactive.props.coerce(InputRowProps, args));
}
pub const InputRowProps = struct {
    unit: ui.Source([]const u8) = .{ .value = "秒" },
    hint: ui.Source([]const u8) = .{ .value = "" },
    off: ui.Source(bool) = .{ .value = false },
    width: ui.Source(?f32) = .{ .value = 180 },
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = InputRow;
    pub const __yix_preview_mount = __yix_InputRow;
};
fn __yix_InputRow(__yix_props: InputRowProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const unit = __yix_props.unit;
    const hint = __yix_props.hint;
    const off = __yix_props.off;
    const width = __yix_props.width;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .unit = unit, .hint = hint, .off = off, .width = width, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, true);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tests/yix_runtime/builder_values.yix", .path = "InputRow", .receiver = "W.Input", .tokens = "< W . Input appendText = { unit } placeholder = { hint } disabled = { off } width = { width } / > ", .literal_text = null, .attributes = &.{ .{ .name = "append_text", .tokens = "unit ", .kind = .property, .literal = null }, .{ .name = "placeholder", .tokens = "hint ", .kind = .property, .literal = null }, .{ .name = "disabled", .tokens = "off ", .kind = .property, .literal = null }, .{ .name = "width", .tokens = "width ", .kind = .property, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .unit = __yix_view_ctx.unit, .hint = __yix_view_ctx.hint, .off = __yix_view_ctx.off, .width = __yix_view_ctx.width, }, __yix_builder_1295: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Input); break :__yix_builder_1295 W.Input(.{ .append_text = __yix_view_ctx.unit, .placeholder = __yix_view_ctx.hint, .disabled = __yix_view_ctx.off, .width = __yix_view_ctx.width, }); }));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "InputRow";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

/// Expressions over a struct parameter: a plain prop and a part's test id.
pub fn ExprRow(args: anytype) ui.view.ComponentOf(__yix_ExprRow) {
    return ui.view.component(__yix_ExprRow, ui.reactive.props.coerce(ExprRowProps, args));
}
pub const ExprRowProps = struct {
    row: ui.Source(Row),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = ExprRow;
    pub const __yix_preview_mount = __yix_ExprRow;
};
fn __yix_ExprRow(__yix_props: ExprRowProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const row = __yix_props.row;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .row = row, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tests/yix_runtime/builder_values.yix", .path = "ExprRow", .receiver = "W.Input", .tokens = "< W . Input appendText = { unitOf ( row ) } parts = { . { . input_container = fieldId ( row ) } } / > ", .literal_text = null, .attributes = &.{ .{ .name = "append_text", .tokens = "unitOf ( row ) ", .kind = .property, .literal = null }, .{ .name = "parts", .tokens = ". { . input_container = fieldId ( row ) } ", .kind = .property, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .row = __yix_view_ctx.row, }, ui.view.templateAttrs(.{ .parts = .{ .input_container = __yix_d2: {
        const __yix_T = @TypeOf(fieldId(__yix_view_ctx.row.peek()));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return fieldId(__yix_ctx.row.get());
        } }.__yix_compute);
    } }, }, __yix_builder_1496: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Input); break :__yix_builder_1496 W.Input(.{ .append_text = __yix_d1: {
        const __yix_T = if (ui.view.attrType(W.Input, "append_text")) |__yix_A| __yix_A else @TypeOf(unitOf(__yix_view_ctx.row.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return unitOf(__yix_ctx.row.get());
        } }.__yix_compute);
    }, }); })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "ExprRow";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

pub fn SelectRow(args: anytype) ui.view.ComponentOf(__yix_SelectRow) {
    return ui.view.component(__yix_SelectRow, ui.reactive.props.coerce(SelectRowProps, args));
}
pub const SelectRowProps = struct {
    options: ui.Source([]const W.SelectOption) = .{ .value = &.{} },
    hint: ui.Source([]const u8) = .{ .value = "" },
    width: ui.Source(f32) = .{ .value = 180 },
    off: ui.Source(bool) = .{ .value = false },
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = SelectRow;
    pub const __yix_preview_mount = __yix_SelectRow;
};
fn __yix_SelectRow(__yix_props: SelectRowProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const options = __yix_props.options;
    const hint = __yix_props.hint;
    const width = __yix_props.width;
    const off = __yix_props.off;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .options = options, .hint = hint, .width = width, .off = off, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, true);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tests/yix_runtime/builder_values.yix", .path = "SelectRow", .receiver = "W.Select", .tokens = "< W . Select options = { options } placeholder = { hint } width = { width } disabled = { off } / > ", .literal_text = null, .attributes = &.{ .{ .name = "options", .tokens = "options ", .kind = .property, .literal = null }, .{ .name = "placeholder", .tokens = "hint ", .kind = .property, .literal = null }, .{ .name = "width", .tokens = "width ", .kind = .property, .literal = null }, .{ .name = "disabled", .tokens = "off ", .kind = .property, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .options = __yix_view_ctx.options, .hint = __yix_view_ctx.hint, .width = __yix_view_ctx.width, .off = __yix_view_ctx.off, }, __yix_builder_1717: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Select); break :__yix_builder_1717 W.Select(.{ .options = __yix_view_ctx.options, .placeholder = __yix_view_ctx.hint, .width = __yix_view_ctx.width, .disabled = __yix_view_ctx.off, }); }));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "SelectRow";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

pub fn TipRow(args: anytype) ui.view.ComponentOf(__yix_TipRow) {
    return ui.view.component(__yix_TipRow, ui.reactive.props.coerce(TipRowProps, args));
}
pub const TipRowProps = struct {
    help: ui.Source([]const u8) = .{ .value = "" },
    width: ui.Source(?f32) = .{ .value = null },
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = TipRow;
    pub const __yix_preview_mount = __yix_TipRow;
};
fn __yix_TipRow(__yix_props: TipRowProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const help = __yix_props.help;
    const width = __yix_props.width;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .help = help, .width = width, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, true);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tests/yix_runtime/builder_values.yix", .path = "TipRow", .receiver = "W.Tooltip", .tokens = "< W . Tooltip text = { help } width = { width } > < text > ? < / text > < / W . Tooltip > ", .literal_text = null, .attributes = &.{ .{ .name = "text", .tokens = "help ", .kind = .property, .literal = null }, .{ .name = "width", .tokens = "width ", .kind = .property, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .help = __yix_view_ctx.help, .width = __yix_view_ctx.width, }, __yix_builder_1885: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Tooltip); break :__yix_builder_1885 ui.view.with(W.Tooltip(.{ .text = __yix_view_ctx.help, .width = __yix_view_ctx.width, }), .{
            ui.view.templateSite(.{ .module = "tests/yix_runtime/builder_values.yix", .path = "TipRow", .receiver = "text", .tokens = "text ", .literal_text = "?", .attributes = &.{ } }, .{ }, ui.view.text(.{ }, ui.view.fmt("?", .{ }))),
        }); }));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "TipRow";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

/// Yix components: every parameter is a source, so these follow the parameters.
pub fn Controls(args: anytype) ui.view.ComponentOf(__yix_Controls) {
    return ui.view.component(__yix_Controls, ui.reactive.props.coerce(ControlsProps, args));
}
pub const ControlsProps = struct {
    title: ui.Source([]const u8) = .{ .value = "" },
    off: ui.Source(bool) = .{ .value = false },
    loading: ui.Source(bool) = .{ .value = false },
    size: ui.Source(W.ButtonSize) = .{ .value = .md },
    on: ui.Source(bool) = .{ .value = false },
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = Controls;
    pub const __yix_preview_mount = __yix_Controls;
};
fn __yix_Controls(__yix_props: ControlsProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const title = __yix_props.title;
    const off = __yix_props.off;
    const loading = __yix_props.loading;
    const size = __yix_props.size;
    const on = __yix_props.on;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .title = title, .off = off, .loading = loading, .size = size, .on = on, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, true);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tests/yix_runtime/builder_values.yix", .path = "Controls", .receiver = "col", .tokens = "col ", .literal_text = null, .attributes = &.{ }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .title = __yix_view_ctx.title, .off = __yix_view_ctx.off, .loading = __yix_view_ctx.loading, .size = __yix_view_ctx.size, .on = __yix_view_ctx.on, }, ui.view.col(.{ }, .{
            ui.view.templateSite(.{ .module = "tests/yix_runtime/builder_values.yix", .path = "Controls", .receiver = "W.Button", .tokens = "< W . Button label = { title } disabled = { off } loading = { loading } size = { size } / > ", .literal_text = null, .attributes = &.{ .{ .name = "label", .tokens = "title ", .kind = .property, .literal = null }, .{ .name = "disabled", .tokens = "off ", .kind = .property, .literal = null }, .{ .name = "loading", .tokens = "loading ", .kind = .property, .literal = null }, .{ .name = "size", .tokens = "size ", .kind = .property, .literal = null }, } }, .{ .title = __yix_view_ctx.title, .off = __yix_view_ctx.off, .loading = __yix_view_ctx.loading, .size = __yix_view_ctx.size, }, __yix_builder_2234: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_2234 W.Button(.{ .label = __yix_view_ctx.title, .disabled = __yix_view_ctx.off, .loading = __yix_view_ctx.loading, .size = __yix_view_ctx.size, }); }),
            ui.view.templateSite(.{ .module = "tests/yix_runtime/builder_values.yix", .path = "Controls", .receiver = "W.Checkbox", .tokens = "< W . Checkbox checked = { on } label = { title } disabled = { off } / > ", .literal_text = null, .attributes = &.{ .{ .name = "checked", .tokens = "on ", .kind = .property, .literal = null }, .{ .name = "label", .tokens = "title ", .kind = .property, .literal = null }, .{ .name = "disabled", .tokens = "off ", .kind = .property, .literal = null }, } }, .{ .on = __yix_view_ctx.on, .title = __yix_view_ctx.title, .off = __yix_view_ctx.off, }, __yix_builder_2318: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Checkbox); break :__yix_builder_2318 W.Checkbox(.{ .checked = __yix_view_ctx.on, .label = __yix_view_ctx.title, .disabled = __yix_view_ctx.off, }); }),
            ui.view.templateSite(.{ .module = "tests/yix_runtime/builder_values.yix", .path = "Controls", .receiver = "W.Switch", .tokens = "< W . Switch checked = { on } label = { title } disabled = { off } / > ", .literal_text = null, .attributes = &.{ .{ .name = "checked", .tokens = "on ", .kind = .property, .literal = null }, .{ .name = "label", .tokens = "title ", .kind = .property, .literal = null }, .{ .name = "disabled", .tokens = "off ", .kind = .property, .literal = null }, } }, .{ .on = __yix_view_ctx.on, .title = __yix_view_ctx.title, .off = __yix_view_ctx.off, }, __yix_builder_2387: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Switch); break :__yix_builder_2387 W.Switch(.{ .checked = __yix_view_ctx.on, .label = __yix_view_ctx.title, .disabled = __yix_view_ctx.off, }); }),
            ui.view.templateSite(.{ .module = "tests/yix_runtime/builder_values.yix", .path = "Controls", .receiver = "W.Radio", .tokens = "< W . Radio checked = { on } label = { title } disabled = { off } / > ", .literal_text = null, .attributes = &.{ .{ .name = "checked", .tokens = "on ", .kind = .property, .literal = null }, .{ .name = "label", .tokens = "title ", .kind = .property, .literal = null }, .{ .name = "disabled", .tokens = "off ", .kind = .property, .literal = null }, } }, .{ .on = __yix_view_ctx.on, .title = __yix_view_ctx.title, .off = __yix_view_ctx.off, }, __yix_builder_2454: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Radio); break :__yix_builder_2454 W.Radio(.{ .checked = __yix_view_ctx.on, .label = __yix_view_ctx.title, .disabled = __yix_view_ctx.off, }); }),
            ui.view.templateSite(.{ .module = "tests/yix_runtime/builder_values.yix", .path = "Controls", .receiver = "W.Tag", .tokens = "< W . Tag label = { title } / > ", .literal_text = null, .attributes = &.{ .{ .name = "label", .tokens = "title ", .kind = .property, .literal = null }, } }, .{ .title = __yix_view_ctx.title, }, __yix_builder_2520: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Tag); break :__yix_builder_2520 W.Tag(.{ .label = __yix_view_ctx.title, }); }),
            ui.view.templateSite(.{ .module = "tests/yix_runtime/builder_values.yix", .path = "Controls", .receiver = "W.Badge", .tokens = "< W . Badge label = { title } / > ", .literal_text = null, .attributes = &.{ .{ .name = "label", .tokens = "title ", .kind = .property, .literal = null }, } }, .{ .title = __yix_view_ctx.title, }, __yix_builder_2556: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Badge); break :__yix_builder_2556 W.Badge(.{ .label = __yix_view_ctx.title, }); }),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "Controls";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

/// G24 forms over a struct parameter: the whole `a11y` value and a part's test id.
pub fn SwitchRow(args: anytype) ui.view.ComponentOf(__yix_SwitchRow) {
    return ui.view.component(__yix_SwitchRow, ui.reactive.props.coerce(SwitchRowProps, args));
}
pub const SwitchRowProps = struct {
    row: ui.Source(Row),
    on: ui.Source(bool) = .{ .value = false },
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = SwitchRow;
    pub const __yix_preview_mount = __yix_SwitchRow;
};
fn __yix_SwitchRow(__yix_props: SwitchRowProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const row = __yix_props.row;
    const on = __yix_props.on;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .row = row, .on = on, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tests/yix_runtime/builder_values.yix", .path = "SwitchRow", .receiver = "W.Switch", .tokens = "< W . Switch checked = { on } a11y = { switchA11y ( row , on ) } testId = { fieldId ( row ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "checked", .tokens = "on ", .kind = .property, .literal = null }, .{ .name = "a11y", .tokens = "switchA11y ( row , on ) ", .kind = .property, .literal = null }, .{ .name = "test_id", .tokens = "fieldId ( row ) ", .kind = .property, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .row = __yix_view_ctx.row, .on = __yix_view_ctx.on, }, ui.view.templateAttrs(.{ .a11y = __yix_d1: {
        const __yix_T = @TypeOf(switchA11y(__yix_view_ctx.row.peek(), __yix_view_ctx.on.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, .on = __yix_view_ctx.on, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return switchA11y(__yix_ctx.row.get(), __yix_ctx.on.get());
        } }.__yix_compute);
    }, .test_id = __yix_d2: {
        const __yix_T = if (ui.view.attrType(W.Switch, "test_id")) |__yix_A| __yix_A else @TypeOf(fieldId(__yix_view_ctx.row.peek()));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return fieldId(__yix_ctx.row.get());
        } }.__yix_compute);
    }, }, __yix_builder_2754: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Switch); break :__yix_builder_2754 W.Switch(.{ .checked = __yix_view_ctx.on, }); })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "SwitchRow";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

/// A builder component's mount result through a handle the caller owns (ZeroWork AI-1: the host
/// keeps the composer's `W.input.TextareaResult` for IME, paste, drop and history): `ref={handle}` binds
/// the builder's own result type, also when the element carries attributes and named slots.
pub fn NoteField(args: anytype) ui.view.ComponentOf(__yix_NoteField) {
    return ui.view.component(__yix_NoteField, ui.reactive.props.coerce(NoteFieldProps, args));
}
pub const NoteFieldProps = struct {
    note: ui.Source(*ui.view.Ref(W.input.TextareaResult)),
    hint: ui.Source([]const u8) = .{ .value = "" },
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = NoteField;
    pub const __yix_preview_mount = __yix_NoteField;
};
fn __yix_NoteField(__yix_props: NoteFieldProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const note = __yix_props.note;
    const hint = __yix_props.hint;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .note = note, .hint = hint, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, true);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tests/yix_runtime/builder_values.yix", .path = "NoteField", .receiver = "W.Textarea", .tokens = "< W . Textarea ref = { note } testId = \"row.note\" placeholder = { hint } visible = { true } header = { < text > chips < / text > } footer = { < text > tools < / text > } / > ", .literal_text = null, .attributes = &.{ .{ .name = "ref", .tokens = "note ", .kind = .reference, .literal = null }, .{ .name = "test_id", .tokens = "\"row.note\" ", .kind = .property, .literal = .{ .text = "row.note" } }, .{ .name = "placeholder", .tokens = "hint ", .kind = .property, .literal = null }, .{ .name = "visible", .tokens = "true ", .kind = .property, .literal = .{ .boolean = true } }, .{ .name = "header", .tokens = "< text > chips < / text > ", .kind = .property, .literal = null }, .{ .name = "footer", .tokens = "< text > tools < / text > ", .kind = .property, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .note = __yix_view_ctx.note, .hint = __yix_view_ctx.hint, }, ui.view.templateAttrs(.{ .test_id = "row.note", .visible = true, }, ui.view.ref(__yix_view_ctx.note, __yix_builder_3241: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Textarea); break :__yix_builder_3241 ui.view.with(W.Textarea(.{ .placeholder = __yix_view_ctx.hint, }), .{ }).slots(.{ .header = ui.view.templateSite(.{ .module = "tests/yix_runtime/builder_values.yix", .path = "NoteField/slot:header", .receiver = "text", .tokens = "text ", .literal_text = "chips", .attributes = &.{ } }, .{ }, ui.view.text(.{ }, ui.view.fmt("chips", .{ }))), .footer = ui.view.templateSite(.{ .module = "tests/yix_runtime/builder_values.yix", .path = "NoteField/slot:footer", .receiver = "text", .tokens = "text ", .literal_text = "tools", .attributes = &.{ } }, .{ }, ui.view.text(.{ }, ui.view.fmt("tools", .{ }))), }); }))));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "NoteField";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

/// The same handle on a plain builder element with no attributes.
pub fn BareNote(args: anytype) ui.view.ComponentOf(__yix_BareNote) {
    return ui.view.component(__yix_BareNote, ui.reactive.props.coerce(BareNoteProps, args));
}
pub const BareNoteProps = struct {
    note: ui.Source(*ui.view.Ref(W.input.TextareaResult)),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = BareNote;
    pub const __yix_preview_mount = __yix_BareNote;
};
fn __yix_BareNote(__yix_props: BareNoteProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const note = __yix_props.note;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .note = note, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, true);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tests/yix_runtime/builder_values.yix", .path = "BareNote", .receiver = "W.Textarea", .tokens = "< W . Textarea ref = { note } / > ", .literal_text = null, .attributes = &.{ .{ .name = "ref", .tokens = "note ", .kind = .reference, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .note = __yix_view_ctx.note, }, ui.view.ref(__yix_view_ctx.note, __yix_builder_3530: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Textarea); break :__yix_builder_3530 W.Textarea(.{ }); })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "BareNote";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

fn keepNote(slot: *?W.input.TextareaResult, note: *ui.view.Ref(W.input.TextareaResult)) void {
    slot.* = note.get();
}

/// A template-local result handle (`ref(W.input.TextareaResult)`), copied out at mount.
pub fn LocalNote(args: anytype) ui.view.ComponentOf(__yix_LocalNote) {
    return ui.view.component(__yix_LocalNote, ui.reactive.props.coerce(LocalNoteProps, args));
}
pub const LocalNoteProps = struct {
    slot: ui.Source(*?W.input.TextareaResult),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = LocalNote;
    pub const __yix_preview_mount = __yix_LocalNote;
};
fn __yix_LocalNote(__yix_props: LocalNoteProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const slot = __yix_props.slot;
    try ui.view.previewCheckSetup(scope, true);
    const note = try ui.view.createRef(scope, W.input.TextareaResult);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .note = note, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, true);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tests/yix_runtime/builder_values.yix", .path = "LocalNote", .receiver = "W.Textarea", .tokens = "< W . Textarea ref = { note } testId = \"row.local\" style = { . { . width = . { . px = 160 } } } / > ", .literal_text = null, .attributes = &.{ .{ .name = "ref", .tokens = "note ", .kind = .reference, .literal = null }, .{ .name = "test_id", .tokens = "\"row.local\" ", .kind = .property, .literal = .{ .text = "row.local" } }, .{ .name = "style", .tokens = ". { . width = . { . px = 160 } } ", .kind = .style, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .note = __yix_view_ctx.note, }, ui.view.templateAttrs(.{ .test_id = "row.local", .style = .{ .width = .{ .px = 160 } }, }, ui.view.ref(__yix_view_ctx.note, __yix_builder_3920: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Textarea); break :__yix_builder_3920 W.Textarea(.{ }); }))));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "LocalNote";
    return __yix_root;
    } }.__yix_render);
    try ui.view.runLifecycleAction(scope, "onMount", .{ .slot = slot, .note = note, .__yix_owner = scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { if (comptime @import("builtin").is_test) __yix_ctx.__yix_owner.recordTestHook(.onMount); __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); keepNote(__yix_ctx.slot.peek(), __yix_ctx.note);  } }.__yix_run);
    return __yix_view;

}

const __yix_preview_source: ?[]const u8 = if (ui.view.template.preview_enabled) "\x2f\x2f\x21\x20\x52\x75\x6e\x74\x69\x6d\x65\x20\x66\x69\x78\x74\x75\x72\x65\x20\x66\x6f\x72\x20\x70\x61\x72\x61\x6d\x65\x74\x65\x72\x73\x20\x66\x6f\x72\x77\x61\x72\x64\x65\x64\x20\x74\x6f\x20\x62\x75\x69\x6c\x64\x65\x72\x20\x77\x69\x64\x67\x65\x74\x20\x70\x72\x6f\x70\x73\x20\x28\x5a\x65\x72\x6f\x57\x6f\x72\x6b\x20\x47\x32\x35\x29\x3a\x20\x61\x20\x72\x6f\x77\x0a\x2f\x2f\x21\x20\x63\x6f\x6d\x70\x6f\x6e\x65\x6e\x74\x20\x70\x61\x73\x73\x65\x73\x20\x69\x74\x73\x20\x70\x61\x72\x61\x6d\x65\x74\x65\x72\x73\x20\x74\x6f\x20\x60\x57\x2e\x49\x6e\x70\x75\x74\x60\x20\x2f\x20\x60\x57\x2e\x53\x65\x6c\x65\x63\x74\x60\x20\x2f\x20\x60\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x60\x20\x61\x73\x20\x77\x72\x69\x74\x74\x65\x6e\x2e\x20\x50\x72\x6f\x70\x73\x0a\x2f\x2f\x21\x20\x74\x79\x70\x65\x64\x20\x60\x75\x69\x2e\x53\x6f\x75\x72\x63\x65\x28\x54\x29\x60\x20\x28\x70\x6c\x61\x63\x65\x68\x6f\x6c\x64\x65\x72\x2c\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x2c\x20\x6f\x70\x74\x69\x6f\x6e\x73\x2c\x20\x74\x65\x78\x74\x29\x20\x66\x6f\x6c\x6c\x6f\x77\x20\x74\x68\x65\x20\x70\x61\x72\x61\x6d\x65\x74\x65\x72\x3b\x20\x70\x6c\x61\x69\x6e\x2d\x76\x61\x6c\x75\x65\x0a\x2f\x2f\x21\x20\x70\x72\x6f\x70\x73\x20\x28\x61\x70\x70\x65\x6e\x64\x54\x65\x78\x74\x2c\x20\x77\x69\x64\x74\x68\x2c\x20\x73\x69\x7a\x65\x29\x20\x74\x61\x6b\x65\x20\x74\x68\x65\x20\x70\x61\x72\x61\x6d\x65\x74\x65\x72\x27\x73\x20\x76\x61\x6c\x75\x65\x20\x6f\x6e\x63\x65\x2c\x20\x77\x68\x65\x6e\x20\x74\x68\x65\x20\x77\x69\x64\x67\x65\x74\x20\x69\x73\x20\x62\x75\x69\x6c\x74\x0a\x2f\x2f\x21\x20\x28\x61\x74\x20\x6d\x6f\x75\x6e\x74\x29\x2e\x20\x41\x6c\x73\x6f\x20\x74\x68\x65\x20\x59\x69\x78\x20\x63\x6f\x6d\x70\x6f\x6e\x65\x6e\x74\x73\x20\x28\x60\x57\x2e\x42\x75\x74\x74\x6f\x6e\x60\x2c\x20\x60\x57\x2e\x53\x77\x69\x74\x63\x68\x60\x2c\x20\xe2\x80\xa6\x29\x2c\x20\x77\x68\x6f\x73\x65\x20\x70\x61\x72\x61\x6d\x65\x74\x65\x72\x73\x20\x61\x72\x65\x20\x61\x6c\x6c\x0a\x2f\x2f\x21\x20\x73\x6f\x75\x72\x63\x65\x73\x2c\x20\x61\x6e\x64\x20\x74\x68\x65\x20\x47\x32\x34\x20\x66\x6f\x72\x6d\x73\x20\x28\x60\x70\x61\x72\x74\x73\x60\x20\x74\x65\x73\x74\x20\x69\x64\x2c\x20\x77\x68\x6f\x6c\x65\x20\x60\x61\x31\x31\x79\x60\x20\x76\x61\x6c\x75\x65\x29\x20\x6f\x76\x65\x72\x20\x61\x20\x73\x74\x72\x75\x63\x74\x20\x70\x61\x72\x61\x6d\x65\x74\x65\x72\x2e\x0a\x2f\x2f\x21\x20\x4c\x69\x76\x65\x73\x20\x6f\x75\x74\x73\x69\x64\x65\x20\x74\x65\x73\x74\x73\x2f\x79\x69\x78\x20\x73\x6f\x20\x69\x74\x20\x69\x73\x20\x6e\x6f\x74\x20\x61\x6e\x20\x4c\x50\x33\x20\x65\x71\x75\x69\x76\x61\x6c\x65\x6e\x63\x65\x20\x69\x6e\x70\x75\x74\x20\x28\x74\x68\x6f\x73\x65\x20\x6e\x65\x65\x64\x20\x72\x65\x76\x69\x65\x77\x65\x64\x20\x67\x6f\x6c\x64\x65\x6e\x73\x29\x2e\x0a\x63\x6f\x6e\x73\x74\x20\x75\x69\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x75\x69\x22\x29\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x57\x20\x3d\x20\x75\x69\x2e\x77\x69\x64\x67\x65\x74\x73\x3b\x0a\x0a\x70\x75\x62\x20\x63\x6f\x6e\x73\x74\x20\x52\x6f\x77\x20\x3d\x20\x73\x74\x72\x75\x63\x74\x20\x7b\x0a\x20\x20\x20\x20\x75\x6e\x69\x74\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x3d\x20\x22\x4d\x42\x22\x2c\x0a\x20\x20\x20\x20\x69\x64\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x3d\x20\x22\x72\x6f\x77\x2e\x66\x69\x65\x6c\x64\x22\x2c\x0a\x20\x20\x20\x20\x6e\x61\x6d\x65\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x3d\x20\x22\x72\x6f\x77\x22\x2c\x0a\x7d\x3b\x0a\x0a\x66\x6e\x20\x75\x6e\x69\x74\x4f\x66\x28\x72\x6f\x77\x3a\x20\x52\x6f\x77\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x72\x6f\x77\x2e\x75\x6e\x69\x74\x3b\x0a\x7d\x0a\x0a\x66\x6e\x20\x66\x69\x65\x6c\x64\x49\x64\x28\x72\x6f\x77\x3a\x20\x52\x6f\x77\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x72\x6f\x77\x2e\x69\x64\x3b\x0a\x7d\x0a\x0a\x66\x6e\x20\x73\x77\x69\x74\x63\x68\x41\x31\x31\x79\x28\x72\x6f\x77\x3a\x20\x52\x6f\x77\x2c\x20\x6f\x6e\x3a\x20\x62\x6f\x6f\x6c\x29\x20\x3f\x75\x69\x2e\x41\x31\x31\x79\x50\x72\x6f\x70\x73\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x2e\x7b\x20\x2e\x72\x6f\x6c\x65\x20\x3d\x20\x2e\x73\x77\x69\x74\x63\x68\x5f\x72\x6f\x6c\x65\x2c\x20\x2e\x63\x68\x65\x63\x6b\x65\x64\x20\x3d\x20\x6f\x6e\x2c\x20\x2e\x6c\x61\x62\x65\x6c\x20\x3d\x20\x72\x6f\x77\x2e\x6e\x61\x6d\x65\x20\x7d\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\x50\x61\x72\x61\x6d\x65\x74\x65\x72\x73\x20\x66\x6f\x72\x77\x61\x72\x64\x65\x64\x20\x61\x73\x20\x77\x72\x69\x74\x74\x65\x6e\x3a\x20\x60\x75\x6e\x69\x74\x60\x20\x2f\x20\x60\x77\x69\x64\x74\x68\x60\x20\x69\x6e\x74\x6f\x20\x70\x6c\x61\x69\x6e\x20\x70\x72\x6f\x70\x73\x2c\x20\x60\x68\x69\x6e\x74\x60\x20\x2f\x20\x60\x6f\x66\x66\x60\x20\x69\x6e\x74\x6f\x20\x73\x6f\x75\x72\x63\x65\x73\x2e\x0a\x70\x75\x62\x20\x66\x6e\x20\x49\x6e\x70\x75\x74\x52\x6f\x77\x28\x75\x6e\x69\x74\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x3d\x20\x22\xe7\xa7\x92\x22\x2c\x20\x68\x69\x6e\x74\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x3d\x20\x22\x22\x2c\x20\x6f\x66\x66\x3a\x20\x62\x6f\x6f\x6c\x20\x3d\x20\x66\x61\x6c\x73\x65\x2c\x20\x77\x69\x64\x74\x68\x3a\x20\x3f\x66\x33\x32\x20\x3d\x20\x31\x38\x30\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x3c\x57\x2e\x49\x6e\x70\x75\x74\x20\x61\x70\x70\x65\x6e\x64\x54\x65\x78\x74\x3d\x7b\x75\x6e\x69\x74\x7d\x20\x70\x6c\x61\x63\x65\x68\x6f\x6c\x64\x65\x72\x3d\x7b\x68\x69\x6e\x74\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x6f\x66\x66\x7d\x20\x77\x69\x64\x74\x68\x3d\x7b\x77\x69\x64\x74\x68\x7d\x20\x2f\x3e\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\x45\x78\x70\x72\x65\x73\x73\x69\x6f\x6e\x73\x20\x6f\x76\x65\x72\x20\x61\x20\x73\x74\x72\x75\x63\x74\x20\x70\x61\x72\x61\x6d\x65\x74\x65\x72\x3a\x20\x61\x20\x70\x6c\x61\x69\x6e\x20\x70\x72\x6f\x70\x20\x61\x6e\x64\x20\x61\x20\x70\x61\x72\x74\x27\x73\x20\x74\x65\x73\x74\x20\x69\x64\x2e\x0a\x70\x75\x62\x20\x66\x6e\x20\x45\x78\x70\x72\x52\x6f\x77\x28\x72\x6f\x77\x3a\x20\x52\x6f\x77\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x3c\x57\x2e\x49\x6e\x70\x75\x74\x20\x61\x70\x70\x65\x6e\x64\x54\x65\x78\x74\x3d\x7b\x75\x6e\x69\x74\x4f\x66\x28\x72\x6f\x77\x29\x7d\x20\x70\x61\x72\x74\x73\x3d\x7b\x2e\x7b\x20\x2e\x69\x6e\x70\x75\x74\x5f\x63\x6f\x6e\x74\x61\x69\x6e\x65\x72\x20\x3d\x20\x66\x69\x65\x6c\x64\x49\x64\x28\x72\x6f\x77\x29\x20\x7d\x7d\x20\x2f\x3e\x3b\x0a\x7d\x0a\x0a\x70\x75\x62\x20\x66\x6e\x20\x53\x65\x6c\x65\x63\x74\x52\x6f\x77\x28\x6f\x70\x74\x69\x6f\x6e\x73\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x57\x2e\x53\x65\x6c\x65\x63\x74\x4f\x70\x74\x69\x6f\x6e\x20\x3d\x20\x26\x2e\x7b\x7d\x2c\x20\x68\x69\x6e\x74\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x3d\x20\x22\x22\x2c\x20\x77\x69\x64\x74\x68\x3a\x20\x66\x33\x32\x20\x3d\x20\x31\x38\x30\x2c\x20\x6f\x66\x66\x3a\x20\x62\x6f\x6f\x6c\x20\x3d\x20\x66\x61\x6c\x73\x65\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x3c\x57\x2e\x53\x65\x6c\x65\x63\x74\x20\x6f\x70\x74\x69\x6f\x6e\x73\x3d\x7b\x6f\x70\x74\x69\x6f\x6e\x73\x7d\x20\x70\x6c\x61\x63\x65\x68\x6f\x6c\x64\x65\x72\x3d\x7b\x68\x69\x6e\x74\x7d\x20\x77\x69\x64\x74\x68\x3d\x7b\x77\x69\x64\x74\x68\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x6f\x66\x66\x7d\x20\x2f\x3e\x3b\x0a\x7d\x0a\x0a\x70\x75\x62\x20\x66\x6e\x20\x54\x69\x70\x52\x6f\x77\x28\x68\x65\x6c\x70\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x3d\x20\x22\x22\x2c\x20\x77\x69\x64\x74\x68\x3a\x20\x3f\x66\x33\x32\x20\x3d\x20\x6e\x75\x6c\x6c\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x20\x74\x65\x78\x74\x3d\x7b\x68\x65\x6c\x70\x7d\x20\x77\x69\x64\x74\x68\x3d\x7b\x77\x69\x64\x74\x68\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x3e\x3f\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\x59\x69\x78\x20\x63\x6f\x6d\x70\x6f\x6e\x65\x6e\x74\x73\x3a\x20\x65\x76\x65\x72\x79\x20\x70\x61\x72\x61\x6d\x65\x74\x65\x72\x20\x69\x73\x20\x61\x20\x73\x6f\x75\x72\x63\x65\x2c\x20\x73\x6f\x20\x74\x68\x65\x73\x65\x20\x66\x6f\x6c\x6c\x6f\x77\x20\x74\x68\x65\x20\x70\x61\x72\x61\x6d\x65\x74\x65\x72\x73\x2e\x0a\x70\x75\x62\x20\x66\x6e\x20\x43\x6f\x6e\x74\x72\x6f\x6c\x73\x28\x74\x69\x74\x6c\x65\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x3d\x20\x22\x22\x2c\x20\x6f\x66\x66\x3a\x20\x62\x6f\x6f\x6c\x20\x3d\x20\x66\x61\x6c\x73\x65\x2c\x20\x6c\x6f\x61\x64\x69\x6e\x67\x3a\x20\x62\x6f\x6f\x6c\x20\x3d\x20\x66\x61\x6c\x73\x65\x2c\x20\x73\x69\x7a\x65\x3a\x20\x57\x2e\x42\x75\x74\x74\x6f\x6e\x53\x69\x7a\x65\x20\x3d\x20\x2e\x6d\x64\x2c\x20\x6f\x6e\x3a\x20\x62\x6f\x6f\x6c\x20\x3d\x20\x66\x61\x6c\x73\x65\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x6c\x61\x62\x65\x6c\x3d\x7b\x74\x69\x74\x6c\x65\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x6f\x66\x66\x7d\x20\x6c\x6f\x61\x64\x69\x6e\x67\x3d\x7b\x6c\x6f\x61\x64\x69\x6e\x67\x7d\x20\x73\x69\x7a\x65\x3d\x7b\x73\x69\x7a\x65\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x43\x68\x65\x63\x6b\x62\x6f\x78\x20\x63\x68\x65\x63\x6b\x65\x64\x3d\x7b\x6f\x6e\x7d\x20\x6c\x61\x62\x65\x6c\x3d\x7b\x74\x69\x74\x6c\x65\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x6f\x66\x66\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x53\x77\x69\x74\x63\x68\x20\x63\x68\x65\x63\x6b\x65\x64\x3d\x7b\x6f\x6e\x7d\x20\x6c\x61\x62\x65\x6c\x3d\x7b\x74\x69\x74\x6c\x65\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x6f\x66\x66\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x52\x61\x64\x69\x6f\x20\x63\x68\x65\x63\x6b\x65\x64\x3d\x7b\x6f\x6e\x7d\x20\x6c\x61\x62\x65\x6c\x3d\x7b\x74\x69\x74\x6c\x65\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x6f\x66\x66\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x54\x61\x67\x20\x6c\x61\x62\x65\x6c\x3d\x7b\x74\x69\x74\x6c\x65\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x61\x64\x67\x65\x20\x6c\x61\x62\x65\x6c\x3d\x7b\x74\x69\x74\x6c\x65\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\x47\x32\x34\x20\x66\x6f\x72\x6d\x73\x20\x6f\x76\x65\x72\x20\x61\x20\x73\x74\x72\x75\x63\x74\x20\x70\x61\x72\x61\x6d\x65\x74\x65\x72\x3a\x20\x74\x68\x65\x20\x77\x68\x6f\x6c\x65\x20\x60\x61\x31\x31\x79\x60\x20\x76\x61\x6c\x75\x65\x20\x61\x6e\x64\x20\x61\x20\x70\x61\x72\x74\x27\x73\x20\x74\x65\x73\x74\x20\x69\x64\x2e\x0a\x70\x75\x62\x20\x66\x6e\x20\x53\x77\x69\x74\x63\x68\x52\x6f\x77\x28\x72\x6f\x77\x3a\x20\x52\x6f\x77\x2c\x20\x6f\x6e\x3a\x20\x62\x6f\x6f\x6c\x20\x3d\x20\x66\x61\x6c\x73\x65\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x3c\x57\x2e\x53\x77\x69\x74\x63\x68\x20\x63\x68\x65\x63\x6b\x65\x64\x3d\x7b\x6f\x6e\x7d\x20\x61\x31\x31\x79\x3d\x7b\x73\x77\x69\x74\x63\x68\x41\x31\x31\x79\x28\x72\x6f\x77\x2c\x20\x6f\x6e\x29\x7d\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x66\x69\x65\x6c\x64\x49\x64\x28\x72\x6f\x77\x29\x7d\x20\x2f\x3e\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\x41\x20\x62\x75\x69\x6c\x64\x65\x72\x20\x63\x6f\x6d\x70\x6f\x6e\x65\x6e\x74\x27\x73\x20\x6d\x6f\x75\x6e\x74\x20\x72\x65\x73\x75\x6c\x74\x20\x74\x68\x72\x6f\x75\x67\x68\x20\x61\x20\x68\x61\x6e\x64\x6c\x65\x20\x74\x68\x65\x20\x63\x61\x6c\x6c\x65\x72\x20\x6f\x77\x6e\x73\x20\x28\x5a\x65\x72\x6f\x57\x6f\x72\x6b\x20\x41\x49\x2d\x31\x3a\x20\x74\x68\x65\x20\x68\x6f\x73\x74\x0a\x2f\x2f\x2f\x20\x6b\x65\x65\x70\x73\x20\x74\x68\x65\x20\x63\x6f\x6d\x70\x6f\x73\x65\x72\x27\x73\x20\x60\x57\x2e\x69\x6e\x70\x75\x74\x2e\x54\x65\x78\x74\x61\x72\x65\x61\x52\x65\x73\x75\x6c\x74\x60\x20\x66\x6f\x72\x20\x49\x4d\x45\x2c\x20\x70\x61\x73\x74\x65\x2c\x20\x64\x72\x6f\x70\x20\x61\x6e\x64\x20\x68\x69\x73\x74\x6f\x72\x79\x29\x3a\x20\x60\x72\x65\x66\x3d\x7b\x68\x61\x6e\x64\x6c\x65\x7d\x60\x20\x62\x69\x6e\x64\x73\x0a\x2f\x2f\x2f\x20\x74\x68\x65\x20\x62\x75\x69\x6c\x64\x65\x72\x27\x73\x20\x6f\x77\x6e\x20\x72\x65\x73\x75\x6c\x74\x20\x74\x79\x70\x65\x2c\x20\x61\x6c\x73\x6f\x20\x77\x68\x65\x6e\x20\x74\x68\x65\x20\x65\x6c\x65\x6d\x65\x6e\x74\x20\x63\x61\x72\x72\x69\x65\x73\x20\x61\x74\x74\x72\x69\x62\x75\x74\x65\x73\x20\x61\x6e\x64\x20\x6e\x61\x6d\x65\x64\x20\x73\x6c\x6f\x74\x73\x2e\x0a\x70\x75\x62\x20\x66\x6e\x20\x4e\x6f\x74\x65\x46\x69\x65\x6c\x64\x28\x6e\x6f\x74\x65\x3a\x20\x2a\x75\x69\x2e\x76\x69\x65\x77\x2e\x52\x65\x66\x28\x57\x2e\x69\x6e\x70\x75\x74\x2e\x54\x65\x78\x74\x61\x72\x65\x61\x52\x65\x73\x75\x6c\x74\x29\x2c\x20\x68\x69\x6e\x74\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x3d\x20\x22\x22\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x54\x65\x78\x74\x61\x72\x65\x61\x20\x72\x65\x66\x3d\x7b\x6e\x6f\x74\x65\x7d\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x72\x6f\x77\x2e\x6e\x6f\x74\x65\x22\x20\x70\x6c\x61\x63\x65\x68\x6f\x6c\x64\x65\x72\x3d\x7b\x68\x69\x6e\x74\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x74\x72\x75\x65\x7d\x20\x68\x65\x61\x64\x65\x72\x3d\x7b\x3c\x74\x65\x78\x74\x3e\x63\x68\x69\x70\x73\x3c\x2f\x74\x65\x78\x74\x3e\x7d\x20\x66\x6f\x6f\x74\x65\x72\x3d\x7b\x3c\x74\x65\x78\x74\x3e\x74\x6f\x6f\x6c\x73\x3c\x2f\x74\x65\x78\x74\x3e\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\x54\x68\x65\x20\x73\x61\x6d\x65\x20\x68\x61\x6e\x64\x6c\x65\x20\x6f\x6e\x20\x61\x20\x70\x6c\x61\x69\x6e\x20\x62\x75\x69\x6c\x64\x65\x72\x20\x65\x6c\x65\x6d\x65\x6e\x74\x20\x77\x69\x74\x68\x20\x6e\x6f\x20\x61\x74\x74\x72\x69\x62\x75\x74\x65\x73\x2e\x0a\x70\x75\x62\x20\x66\x6e\x20\x42\x61\x72\x65\x4e\x6f\x74\x65\x28\x6e\x6f\x74\x65\x3a\x20\x2a\x75\x69\x2e\x76\x69\x65\x77\x2e\x52\x65\x66\x28\x57\x2e\x69\x6e\x70\x75\x74\x2e\x54\x65\x78\x74\x61\x72\x65\x61\x52\x65\x73\x75\x6c\x74\x29\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x3c\x57\x2e\x54\x65\x78\x74\x61\x72\x65\x61\x20\x72\x65\x66\x3d\x7b\x6e\x6f\x74\x65\x7d\x20\x2f\x3e\x3b\x0a\x7d\x0a\x0a\x66\x6e\x20\x6b\x65\x65\x70\x4e\x6f\x74\x65\x28\x73\x6c\x6f\x74\x3a\x20\x2a\x3f\x57\x2e\x69\x6e\x70\x75\x74\x2e\x54\x65\x78\x74\x61\x72\x65\x61\x52\x65\x73\x75\x6c\x74\x2c\x20\x6e\x6f\x74\x65\x3a\x20\x2a\x75\x69\x2e\x76\x69\x65\x77\x2e\x52\x65\x66\x28\x57\x2e\x69\x6e\x70\x75\x74\x2e\x54\x65\x78\x74\x61\x72\x65\x61\x52\x65\x73\x75\x6c\x74\x29\x29\x20\x76\x6f\x69\x64\x20\x7b\x0a\x20\x20\x20\x20\x73\x6c\x6f\x74\x2e\x2a\x20\x3d\x20\x6e\x6f\x74\x65\x2e\x67\x65\x74\x28\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\x41\x20\x74\x65\x6d\x70\x6c\x61\x74\x65\x2d\x6c\x6f\x63\x61\x6c\x20\x72\x65\x73\x75\x6c\x74\x20\x68\x61\x6e\x64\x6c\x65\x20\x28\x60\x72\x65\x66\x28\x57\x2e\x69\x6e\x70\x75\x74\x2e\x54\x65\x78\x74\x61\x72\x65\x61\x52\x65\x73\x75\x6c\x74\x29\x60\x29\x2c\x20\x63\x6f\x70\x69\x65\x64\x20\x6f\x75\x74\x20\x61\x74\x20\x6d\x6f\x75\x6e\x74\x2e\x0a\x70\x75\x62\x20\x66\x6e\x20\x4c\x6f\x63\x61\x6c\x4e\x6f\x74\x65\x28\x73\x6c\x6f\x74\x3a\x20\x2a\x3f\x57\x2e\x69\x6e\x70\x75\x74\x2e\x54\x65\x78\x74\x61\x72\x65\x61\x52\x65\x73\x75\x6c\x74\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x6e\x6f\x74\x65\x20\x3d\x20\x72\x65\x66\x28\x57\x2e\x69\x6e\x70\x75\x74\x2e\x54\x65\x78\x74\x61\x72\x65\x61\x52\x65\x73\x75\x6c\x74\x29\x3b\x0a\x20\x20\x20\x20\x6f\x6e\x4d\x6f\x75\x6e\x74\x28\x6b\x65\x65\x70\x4e\x6f\x74\x65\x28\x73\x6c\x6f\x74\x2c\x20\x6e\x6f\x74\x65\x29\x29\x3b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x3c\x57\x2e\x54\x65\x78\x74\x61\x72\x65\x61\x20\x72\x65\x66\x3d\x7b\x6e\x6f\x74\x65\x7d\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x72\x6f\x77\x2e\x6c\x6f\x63\x61\x6c\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x2e\x7b\x20\x2e\x77\x69\x64\x74\x68\x20\x3d\x20\x2e\x7b\x20\x2e\x70\x78\x20\x3d\x20\x31\x36\x30\x20\x7d\x20\x7d\x7d\x20\x2f\x3e\x3b\x0a\x7d\x0a" else null;
const __YixStyleCatalog = if (ui.view.template.preview_enabled) ui.view.template.styleCatalog(.{ }) else void;

//# yix-map-data [[1178,1178],[3745,1457],[6335,1586],[8870,1804],[11188,2066],[17631,2695],[20783,3133],[23980,3456],[25902,3776]]

//# yix-map builder_values.yix
