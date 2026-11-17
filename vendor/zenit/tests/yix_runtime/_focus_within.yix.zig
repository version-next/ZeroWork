// GENERATED FILE, do not edit: generated from focus_within.yix; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! Runtime fixture for focus-within events (ZeroWork G31): a host container and a component
//! element (`W.Pressable`, whose root is the focusable node) report focus entering / leaving
//! their subtree. Lives outside tests/yix so it is not an LP3 equivalence input.
const ui = @import("ui");
const W = ui.widgets;

pub const Log = struct {
    entered: usize = 0,
    left: usize = 0,
    root_entered: usize = 0,
    root_left: usize = 0,
};

fn enter(log: *Log) void {
    log.entered += 1;
}
fn leave(log: *Log) void {
    log.left += 1;
}
fn rootEnter(log: *Log) void {
    log.root_entered += 1;
}
fn rootLeave(log: *Log) void {
    log.root_left += 1;
}

pub fn Panel(args: anytype) ui.view.ComponentOf(__yix_Panel) {
    return ui.view.component(__yix_Panel, ui.reactive.props.coerce(PanelProps, args));
}
pub const PanelProps = struct {
    log: ui.Source(*Log),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = Panel;
    pub const __yix_preview_mount = __yix_Panel;
};
fn __yix_Panel(__yix_props: PanelProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const log = __yix_props.log;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .log = log, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tests/yix_runtime/focus_within.yix", .path = "Panel", .receiver = "col", .tokens = "col testId = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"fw.panel\" ", .kind = .property, .literal = .{ .text = "fw.panel" } }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .log = __yix_view_ctx.log, }, ui.view.col(.{ .test_id = "fw.panel", }, .{
            ui.view.templateSite(.{ .module = "tests/yix_runtime/focus_within.yix", .path = "Panel", .receiver = "box", .tokens = "box testId = @static; onFocusWithin = enter ( log ) ; onBlurWithin = leave ( log ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"fw.slot\" ", .kind = .property, .literal = .{ .text = "fw.slot" } }, .{ .name = "on_focus_within", .tokens = "enter ( log ) ", .kind = .event, .literal = null }, .{ .name = "on_blur_within", .tokens = "leave ( log ) ", .kind = .event, .literal = null }, } }, .{ .log = __yix_view_ctx.log, }, ui.view.box(.{ .test_id = "fw.slot", .on_focus_within = try ui.on.bind(__yix_view_scope, .{ .log = __yix_view_ctx.log, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); enter(__yix_ctx.log.peek());  } }.__yix_run), .on_blur_within = try ui.on.bind(__yix_view_scope, .{ .log = __yix_view_ctx.log, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); leave(__yix_ctx.log.peek());  } }.__yix_run), }, .{
                ui.view.templateSite(.{ .module = "tests/yix_runtime/focus_within.yix", .path = "Panel", .receiver = "W.Button", .tokens = "< W . Button testId = \"fw.a\" label = \"A\" / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"fw.a\" ", .kind = .property, .literal = .{ .text = "fw.a" } }, .{ .name = "label", .tokens = "\"A\" ", .kind = .property, .literal = .{ .text = "A" } }, } }, .{ }, ui.view.templateAttrs(.{ .test_id = "fw.a", }, __yix_builder_844: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_844 W.Button(.{ .label = "A", }); })),
                ui.view.templateSite(.{ .module = "tests/yix_runtime/focus_within.yix", .path = "Panel", .receiver = "W.Button", .tokens = "< W . Button testId = \"fw.b\" label = \"B\" / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"fw.b\" ", .kind = .property, .literal = .{ .text = "fw.b" } }, .{ .name = "label", .tokens = "\"B\" ", .kind = .property, .literal = .{ .text = "B" } }, } }, .{ }, ui.view.templateAttrs(.{ .test_id = "fw.b", }, __yix_builder_897: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_897 W.Button(.{ .label = "B", }); })),
            })),
            ui.view.templateSite(.{ .module = "tests/yix_runtime/focus_within.yix", .path = "Panel", .receiver = "W.Pressable", .tokens = "< W . Pressable testId = \"fw.press\" onFocusWithin = { rootEnter ( log ) } onBlurWithin = { rootLeave ( log ) } > < text > Press < / text > < / W . Pressable > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"fw.press\" ", .kind = .property, .literal = .{ .text = "fw.press" } }, .{ .name = "on_focus_within", .tokens = "rootEnter ( log ) ", .kind = .event, .literal = null }, .{ .name = "on_blur_within", .tokens = "rootLeave ( log ) ", .kind = .event, .literal = null }, } }, .{ .log = __yix_view_ctx.log, }, ui.view.templateAttrs(.{ .test_id = "fw.press", .on_focus_within = if (comptime ui.view.isEventProp(W.Pressable, "on_focus_within")) try ui.on.bindAny(__yix_view_scope, .{ .log = __yix_view_ctx.log, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); rootEnter(__yix_ctx.log.peek());  } }.__yix_run) else __yix_d1: {
        const __yix_T = if (ui.view.attrType(W.Pressable, "on_focus_within")) |__yix_A| __yix_A else @TypeOf(rootEnter(__yix_view_ctx.log.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .log = __yix_view_ctx.log, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return rootEnter(__yix_ctx.log.get());
        } }.__yix_compute);
    }, .on_blur_within = if (comptime ui.view.isEventProp(W.Pressable, "on_blur_within")) try ui.on.bindAny(__yix_view_scope, .{ .log = __yix_view_ctx.log, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); rootLeave(__yix_ctx.log.peek());  } }.__yix_run) else __yix_d2: {
        const __yix_T = if (ui.view.attrType(W.Pressable, "on_blur_within")) |__yix_A| __yix_A else @TypeOf(rootLeave(__yix_view_ctx.log.peek()));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .log = __yix_view_ctx.log, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return rootLeave(__yix_ctx.log.get());
        } }.__yix_compute);
    }, }, __yix_builder_965: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Pressable); break :__yix_builder_965 ui.view.with(W.Pressable(.{ }), .{
                ui.view.templateSite(.{ .module = "tests/yix_runtime/focus_within.yix", .path = "Panel", .receiver = "text", .tokens = "text ", .literal_text = "Press", .attributes = &.{ } }, .{ }, ui.view.text(.{ }, ui.view.fmt("Press", .{ }))),
            }); })),
            ui.view.templateSite(.{ .module = "tests/yix_runtime/focus_within.yix", .path = "Panel", .receiver = "W.Button", .tokens = "< W . Button testId = \"fw.outside\" label = \"Outside\" / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"fw.outside\" ", .kind = .property, .literal = .{ .text = "fw.outside" } }, .{ .name = "label", .tokens = "\"Outside\" ", .kind = .property, .literal = .{ .text = "Outside" } }, } }, .{ }, ui.view.templateAttrs(.{ .test_id = "fw.outside", }, __yix_builder_1132: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_1132 W.Button(.{ .label = "Outside", }); })),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "Panel";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

const __yix_preview_source: ?[]const u8 = if (ui.view.template.preview_enabled) "\x2f\x2f\x21\x20\x52\x75\x6e\x74\x69\x6d\x65\x20\x66\x69\x78\x74\x75\x72\x65\x20\x66\x6f\x72\x20\x66\x6f\x63\x75\x73\x2d\x77\x69\x74\x68\x69\x6e\x20\x65\x76\x65\x6e\x74\x73\x20\x28\x5a\x65\x72\x6f\x57\x6f\x72\x6b\x20\x47\x33\x31\x29\x3a\x20\x61\x20\x68\x6f\x73\x74\x20\x63\x6f\x6e\x74\x61\x69\x6e\x65\x72\x20\x61\x6e\x64\x20\x61\x20\x63\x6f\x6d\x70\x6f\x6e\x65\x6e\x74\x0a\x2f\x2f\x21\x20\x65\x6c\x65\x6d\x65\x6e\x74\x20\x28\x60\x57\x2e\x50\x72\x65\x73\x73\x61\x62\x6c\x65\x60\x2c\x20\x77\x68\x6f\x73\x65\x20\x72\x6f\x6f\x74\x20\x69\x73\x20\x74\x68\x65\x20\x66\x6f\x63\x75\x73\x61\x62\x6c\x65\x20\x6e\x6f\x64\x65\x29\x20\x72\x65\x70\x6f\x72\x74\x20\x66\x6f\x63\x75\x73\x20\x65\x6e\x74\x65\x72\x69\x6e\x67\x20\x2f\x20\x6c\x65\x61\x76\x69\x6e\x67\x0a\x2f\x2f\x21\x20\x74\x68\x65\x69\x72\x20\x73\x75\x62\x74\x72\x65\x65\x2e\x20\x4c\x69\x76\x65\x73\x20\x6f\x75\x74\x73\x69\x64\x65\x20\x74\x65\x73\x74\x73\x2f\x79\x69\x78\x20\x73\x6f\x20\x69\x74\x20\x69\x73\x20\x6e\x6f\x74\x20\x61\x6e\x20\x4c\x50\x33\x20\x65\x71\x75\x69\x76\x61\x6c\x65\x6e\x63\x65\x20\x69\x6e\x70\x75\x74\x2e\x0a\x63\x6f\x6e\x73\x74\x20\x75\x69\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x75\x69\x22\x29\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x57\x20\x3d\x20\x75\x69\x2e\x77\x69\x64\x67\x65\x74\x73\x3b\x0a\x0a\x70\x75\x62\x20\x63\x6f\x6e\x73\x74\x20\x4c\x6f\x67\x20\x3d\x20\x73\x74\x72\x75\x63\x74\x20\x7b\x0a\x20\x20\x20\x20\x65\x6e\x74\x65\x72\x65\x64\x3a\x20\x75\x73\x69\x7a\x65\x20\x3d\x20\x30\x2c\x0a\x20\x20\x20\x20\x6c\x65\x66\x74\x3a\x20\x75\x73\x69\x7a\x65\x20\x3d\x20\x30\x2c\x0a\x20\x20\x20\x20\x72\x6f\x6f\x74\x5f\x65\x6e\x74\x65\x72\x65\x64\x3a\x20\x75\x73\x69\x7a\x65\x20\x3d\x20\x30\x2c\x0a\x20\x20\x20\x20\x72\x6f\x6f\x74\x5f\x6c\x65\x66\x74\x3a\x20\x75\x73\x69\x7a\x65\x20\x3d\x20\x30\x2c\x0a\x7d\x3b\x0a\x0a\x66\x6e\x20\x65\x6e\x74\x65\x72\x28\x6c\x6f\x67\x3a\x20\x2a\x4c\x6f\x67\x29\x20\x76\x6f\x69\x64\x20\x7b\x0a\x20\x20\x20\x20\x6c\x6f\x67\x2e\x65\x6e\x74\x65\x72\x65\x64\x20\x2b\x3d\x20\x31\x3b\x0a\x7d\x0a\x66\x6e\x20\x6c\x65\x61\x76\x65\x28\x6c\x6f\x67\x3a\x20\x2a\x4c\x6f\x67\x29\x20\x76\x6f\x69\x64\x20\x7b\x0a\x20\x20\x20\x20\x6c\x6f\x67\x2e\x6c\x65\x66\x74\x20\x2b\x3d\x20\x31\x3b\x0a\x7d\x0a\x66\x6e\x20\x72\x6f\x6f\x74\x45\x6e\x74\x65\x72\x28\x6c\x6f\x67\x3a\x20\x2a\x4c\x6f\x67\x29\x20\x76\x6f\x69\x64\x20\x7b\x0a\x20\x20\x20\x20\x6c\x6f\x67\x2e\x72\x6f\x6f\x74\x5f\x65\x6e\x74\x65\x72\x65\x64\x20\x2b\x3d\x20\x31\x3b\x0a\x7d\x0a\x66\x6e\x20\x72\x6f\x6f\x74\x4c\x65\x61\x76\x65\x28\x6c\x6f\x67\x3a\x20\x2a\x4c\x6f\x67\x29\x20\x76\x6f\x69\x64\x20\x7b\x0a\x20\x20\x20\x20\x6c\x6f\x67\x2e\x72\x6f\x6f\x74\x5f\x6c\x65\x66\x74\x20\x2b\x3d\x20\x31\x3b\x0a\x7d\x0a\x0a\x70\x75\x62\x20\x66\x6e\x20\x50\x61\x6e\x65\x6c\x28\x6c\x6f\x67\x3a\x20\x2a\x4c\x6f\x67\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x63\x6f\x6c\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x66\x77\x2e\x70\x61\x6e\x65\x6c\x22\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x66\x77\x2e\x73\x6c\x6f\x74\x22\x20\x6f\x6e\x46\x6f\x63\x75\x73\x57\x69\x74\x68\x69\x6e\x3d\x7b\x65\x6e\x74\x65\x72\x28\x6c\x6f\x67\x29\x7d\x20\x6f\x6e\x42\x6c\x75\x72\x57\x69\x74\x68\x69\x6e\x3d\x7b\x6c\x65\x61\x76\x65\x28\x6c\x6f\x67\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x66\x77\x2e\x61\x22\x20\x6c\x61\x62\x65\x6c\x3d\x22\x41\x22\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x66\x77\x2e\x62\x22\x20\x6c\x61\x62\x65\x6c\x3d\x22\x42\x22\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x50\x72\x65\x73\x73\x61\x62\x6c\x65\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x66\x77\x2e\x70\x72\x65\x73\x73\x22\x20\x6f\x6e\x46\x6f\x63\x75\x73\x57\x69\x74\x68\x69\x6e\x3d\x7b\x72\x6f\x6f\x74\x45\x6e\x74\x65\x72\x28\x6c\x6f\x67\x29\x7d\x20\x6f\x6e\x42\x6c\x75\x72\x57\x69\x74\x68\x69\x6e\x3d\x7b\x72\x6f\x6f\x74\x4c\x65\x61\x76\x65\x28\x6c\x6f\x67\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x3e\x50\x72\x65\x73\x73\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x50\x72\x65\x73\x73\x61\x62\x6c\x65\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x66\x77\x2e\x6f\x75\x74\x73\x69\x64\x65\x22\x20\x6c\x61\x62\x65\x6c\x3d\x22\x4f\x75\x74\x73\x69\x64\x65\x22\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a" else null;
const __YixStyleCatalog = if (ui.view.template.preview_enabled) ui.view.template.styleCatalog(.{ }) else void;

//# yix-map-data [[668,668]]

//# yix-map focus_within.yix
