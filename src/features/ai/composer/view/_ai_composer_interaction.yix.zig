// GENERATED FILE, do not edit: generated from ai_composer_interaction.yix; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! The composer's decision panel (Pencil Kaf7E A7 approval / A11 question): while a request is
//! pending it takes the composer's place — a native outlined `W.Card` holding the heading, the
//! command well with a copy `W.Button` (+ `W.Tooltip`), the impact note, the run-mode choice
//! (native segmented `W.Tabs` sm), the question's native `W.RadioGroup` (+ a `W.Input` for a custom
//! answer) and the action row (ghost “稍后处理”, secondary “拒绝”, primary “允许执行” / “提交答案”).
//! “稍后处理” folds it into a native secondary sm `W.Button` capsule above the composer
//! (`PendingCapsule`). State, tickets and decisions live in the view-model
//! (`ai_composer_interaction_view.zig`); this file is the view only.
const ui = @import("ui");
const W = ui.widgets;
const S = @import("_ai_composer_interaction.yss.zig");
const M = @import("ai_composer_interaction_view.zig");

fn keep(m: *M.View, viewport: *ui.view.Ref(W.scroll_area.ScrollAreaResult), accept: *ui.view.Ref(*ui.Node), reject: *ui.view.Ref(*ui.Node), submit: *ui.view.Ref(*ui.Node), answer: *ui.view.Ref(W.input.InputResult)) void {
    m.keep(viewport.get(), accept.get(), reject.get(), submit.get(), answer);
}

pub fn Interaction(args: anytype) ui.view.ComponentOf(__yix_Interaction) {
    return ui.view.component(__yix_Interaction, ui.reactive.props.coerce(InteractionProps, args));
}
pub const InteractionProps = struct {
    m: ui.Source(*M.View),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = Interaction;
    pub const __yix_preview_mount = __yix_Interaction;
};
fn __yix_Interaction(__yix_props: InteractionProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const m = __yix_props.m;
    try ui.view.previewCheckSetup(scope, true);
    const viewport = try ui.view.createRef(scope, W.scroll_area.ScrollAreaResult);
    const accept = try ui.view.createRef(scope, *ui.Node);
    const reject = try ui.view.createRef(scope, *ui.Node);
    const submit = try ui.view.createRef(scope, *ui.Node);
    const answer = try ui.view.createRef(scope, W.input.InputResult);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .m = m, .viewport = viewport, .accept = accept, .reject = reject, .submit = submit, .answer = answer, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_interaction.yix", .path = "Interaction", .receiver = "W.Card", .tokens = "< W . Card testId = { m . space . id ( \"ai.interaction.card\" ) } variant = { . outlined } padded = { false } visible = { M . expanded ( m ) } > < col style = { S . body } focusRequest = { M . focus ( m ) } > < W . ScrollArea ref = { viewport } direction = { . vertical } overscrollY = { . contain } scrollbars = { . always } scrollbarGutter = { . stable } testId = { m . space . id ( \"ai.interaction.panel\" ) } style = { S . viewport . of ( . { . max = M . maxBody ( m ) } ) } parts = { . { . content = . { . style = S . content } } } > < row style = { S . heading } > < icon src = { M . glyph ( \"shield-alert\" ) } style = { S . warn_glyph } visible = { ! M . isQuestion ( m ) } / > < icon src = { M . glyph ( \"message-circle-question\" ) } style = { S . ask_glyph } visible = { M . isQuestion ( m ) } / > < col style = { S . title_block } > < text testId = { m . space . id ( \"ai.interaction.title\" ) } style = { S . title } box = { S . fill_text } > { M . title ( m ) } < / text > < text testId = { m . space . id ( \"ai.interaction.target\" ) } style = { S . secondary } box = { S . fill_text } visible = { M . targetShown ( m ) } > { M . target ( m ) } < / text > < / col > < / row > < row style = { S . command_row } visible = { M . commandShown ( m ) } > < text testId = { m . space . id ( \"ai.interaction.command\" ) } style = { S . command } box = { S . command_well } > { M . detail ( m ) } < / text > < W . Tooltip text = \"复制命令或详情\" position = { . top } > < W . Button testId = { m . space . id ( \"ai.interaction.copy\" ) } variant = { . ghost } size = { . sm } iconOnly = { true } iconAsset = { M . glyph ( \"copy\" ) } a11yLabel = \"复制命令或详情\" onClick = { M . copyDetail ( m ) } / > < / W . Tooltip > < / row > < row testId = { m . space . id ( \"ai.interaction.impact.note\" ) } style = { S . impact_row } visible = { M . impactShown ( m ) } > < icon src = { M . glyph ( \"info\" ) } style = { S . info_glyph } / > < text testId = { m . space . id ( \"ai.interaction.impact\" ) } style = { S . secondary } box = { S . row_text } > { M . impact ( m ) } < / text > < / row > < W . Tabs testId = { m . space . id ( \"ai.interaction.route\" ) } items = { M . routeItems ( m ) } variant = { . segmented } size = { . sm } active = { M . routeActive ( m ) } onChange = { | id | M . chooseRoute ( m , id ) } visible = { M . routeShown ( m ) } / > < text style = { S . reason } box = { S . fill_text } visible = { M . reasonShown ( m ) } > { M . routeReason ( m ) } < / text > < col style = { S . options } visible = { M . optionsShown ( m ) } > < W . RadioGroup options = { M . radioOptions ( m ) } value = { M . selectedValue ( m ) } disabled = { M . locked ( m ) } onChange = { | v | M . selectionChanged ( m , v ) } / > < / col > < row testId = { m . space . id ( \"ai.interaction.custom\" ) } style = { S . custom_row } visible = { M . customShown ( m ) } > < W . Input ref = { answer } value = { M . customText ( m ) } placeholder = \"输入你的答案…\" size = { . sm } disabled = { M . locked ( m ) } focusId = \"ai.interaction.answer\" parts = { . { . input_container = m . space . id ( \"ai.interaction.answer\" ) } } onChange = { | t | M . customChanged ( m , t ) } / > < / row > < text testId = { m . space . id ( \"ai.interaction.error\" ) } style = { S . failure } box = { S . fill_text } visible = { M . errorShown ( m ) } > { M . errorText ( m ) } < / text > < / W . ScrollArea > < row testId = { m . space . id ( \"ai.interaction.actions\" ) } style = { S . actions } > < spacer / > < W . Button testId = { m . space . id ( \"ai.interaction.postpone\" ) } label = \"稍后处理\" variant = { . ghost } size = { . sm } disabled = { M . locked ( m ) } onClick = { M . postpone ( m ) } / > < W . Button ref = { reject } testId = { m . space . id ( \"ai.interaction.reject\" ) } label = \"拒绝\" iconAsset = { M . glyph ( \"x\" ) } variant = { . secondary } size = { . sm } disabled = { M . locked ( m ) } visible = { ! M . isQuestion ( m ) } onClick = { M . deny ( m ) } / > < W . Button ref = { accept } testId = { m . space . id ( \"ai.interaction.approve\" ) } label = \"允许执行\" iconAsset = { M . glyph ( \"check\" ) } variant = { . primary } size = { . sm } disabled = { M . locked ( m ) } visible = { ! M . isQuestion ( m ) } onClick = { M . approve ( m ) } / > < W . Button ref = { submit } testId = { m . space . id ( \"ai.interaction.submit\" ) } label = \"提交答案\" iconAsset = { M . glyph ( \"check\" ) } variant = { . primary } size = { . sm } disabled = { M . locked ( m ) } visible = { M . isQuestion ( m ) } onClick = { M . submit ( m ) } / > < / row > < / col > < / W . Card > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "m . space . id ( \"ai.interaction.card\" ) ", .kind = .property, .literal = null }, .{ .name = "variant", .tokens = ". outlined ", .kind = .property, .literal = .{ .enum_name = "outlined" } }, .{ .name = "padded", .tokens = "false ", .kind = .property, .literal = .{ .boolean = false } }, .{ .name = "visible", .tokens = "M . expanded ( m ) ", .kind = .property, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .m = __yix_view_ctx.m, .viewport = __yix_view_ctx.viewport, .answer = __yix_view_ctx.answer, .reject = __yix_view_ctx.reject, .accept = __yix_view_ctx.accept, .submit = __yix_view_ctx.submit, }, ui.view.templateAttrs(.{ .test_id = __yix_d1: {
        const __yix_T = if (ui.view.attrType(W.Card, "test_id")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.m.peek().space.id("ai.interaction.card"));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.interaction.card");
        } }.__yix_compute);
    }, .visible = __yix_d2: {
        const __yix_T = if (ui.view.attrType(W.Card, "visible")) |__yix_A| __yix_A else @TypeOf(M.expanded(__yix_view_ctx.m.peek()));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.expanded(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }, __yix_builder_1525: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Card); break :__yix_builder_1525 ui.view.with(W.Card(.{ .variant = .outlined, .padded = false, }), .{
            ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_interaction.yix", .path = "Interaction", .receiver = "col", .tokens = "col style = @static; focusRequest = M . focus ( m ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . body ", .kind = .style, .literal = null }, .{ .name = "focus_request", .tokens = "M . focus ( m ) ", .kind = .property, .literal = null }, } }, .{ .m = __yix_view_ctx.m, .viewport = __yix_view_ctx.viewport, .answer = __yix_view_ctx.answer, .reject = __yix_view_ctx.reject, .accept = __yix_view_ctx.accept, .submit = __yix_view_ctx.submit, }, ui.view.col(.{ .style = S.body, .focus_request = __yix_d3: {
        const __yix_T = @TypeOf(M.focus(__yix_view_ctx.m.peek()));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.focus(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }, .{
                ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_interaction.yix", .path = "Interaction", .receiver = "W.ScrollArea", .tokens = "< W . ScrollArea ref = { viewport } direction = { . vertical } overscrollY = { . contain } scrollbars = { . always } scrollbarGutter = { . stable } testId = { m . space . id ( \"ai.interaction.panel\" ) } style = { S . viewport . of ( . { . max = M . maxBody ( m ) } ) } parts = { . { . content = . { . style = S . content } } } > < row style = { S . heading } > < icon src = { M . glyph ( \"shield-alert\" ) } style = { S . warn_glyph } visible = { ! M . isQuestion ( m ) } / > < icon src = { M . glyph ( \"message-circle-question\" ) } style = { S . ask_glyph } visible = { M . isQuestion ( m ) } / > < col style = { S . title_block } > < text testId = { m . space . id ( \"ai.interaction.title\" ) } style = { S . title } box = { S . fill_text } > { M . title ( m ) } < / text > < text testId = { m . space . id ( \"ai.interaction.target\" ) } style = { S . secondary } box = { S . fill_text } visible = { M . targetShown ( m ) } > { M . target ( m ) } < / text > < / col > < / row > < row style = { S . command_row } visible = { M . commandShown ( m ) } > < text testId = { m . space . id ( \"ai.interaction.command\" ) } style = { S . command } box = { S . command_well } > { M . detail ( m ) } < / text > < W . Tooltip text = \"复制命令或详情\" position = { . top } > < W . Button testId = { m . space . id ( \"ai.interaction.copy\" ) } variant = { . ghost } size = { . sm } iconOnly = { true } iconAsset = { M . glyph ( \"copy\" ) } a11yLabel = \"复制命令或详情\" onClick = { M . copyDetail ( m ) } / > < / W . Tooltip > < / row > < row testId = { m . space . id ( \"ai.interaction.impact.note\" ) } style = { S . impact_row } visible = { M . impactShown ( m ) } > < icon src = { M . glyph ( \"info\" ) } style = { S . info_glyph } / > < text testId = { m . space . id ( \"ai.interaction.impact\" ) } style = { S . secondary } box = { S . row_text } > { M . impact ( m ) } < / text > < / row > < W . Tabs testId = { m . space . id ( \"ai.interaction.route\" ) } items = { M . routeItems ( m ) } variant = { . segmented } size = { . sm } active = { M . routeActive ( m ) } onChange = { | id | M . chooseRoute ( m , id ) } visible = { M . routeShown ( m ) } / > < text style = { S . reason } box = { S . fill_text } visible = { M . reasonShown ( m ) } > { M . routeReason ( m ) } < / text > < col style = { S . options } visible = { M . optionsShown ( m ) } > < W . RadioGroup options = { M . radioOptions ( m ) } value = { M . selectedValue ( m ) } disabled = { M . locked ( m ) } onChange = { | v | M . selectionChanged ( m , v ) } / > < / col > < row testId = { m . space . id ( \"ai.interaction.custom\" ) } style = { S . custom_row } visible = { M . customShown ( m ) } > < W . Input ref = { answer } value = { M . customText ( m ) } placeholder = \"输入你的答案…\" size = { . sm } disabled = { M . locked ( m ) } focusId = \"ai.interaction.answer\" parts = { . { . input_container = m . space . id ( \"ai.interaction.answer\" ) } } onChange = { | t | M . customChanged ( m , t ) } / > < / row > < text testId = { m . space . id ( \"ai.interaction.error\" ) } style = { S . failure } box = { S . fill_text } visible = { M . errorShown ( m ) } > { M . errorText ( m ) } < / text > < / W . ScrollArea > ", .literal_text = null, .attributes = &.{ .{ .name = "ref", .tokens = "viewport ", .kind = .reference, .literal = null }, .{ .name = "direction", .tokens = ". vertical ", .kind = .property, .literal = .{ .enum_name = "vertical" } }, .{ .name = "overscroll_y", .tokens = ". contain ", .kind = .property, .literal = .{ .enum_name = "contain" } }, .{ .name = "scrollbars", .tokens = ". always ", .kind = .property, .literal = .{ .enum_name = "always" } }, .{ .name = "scrollbar_gutter", .tokens = ". stable ", .kind = .property, .literal = .{ .enum_name = "stable" } }, .{ .name = "test_id", .tokens = "m . space . id ( \"ai.interaction.panel\" ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . viewport . of ( . { . max = M . maxBody ( m ) } ) ", .kind = .style, .literal = null }, .{ .name = "parts", .tokens = ". { . content = . { . style = S . content } } ", .kind = .property, .literal = null }, } }, .{ .m = __yix_view_ctx.m, .viewport = __yix_view_ctx.viewport, .answer = __yix_view_ctx.answer, }, ui.view.templateAttrs(.{ .test_id = __yix_d4: {
        const __yix_T = if (ui.view.attrType(W.ScrollArea, "test_id")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.m.peek().space.id("ai.interaction.panel"));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.interaction.panel");
        } }.__yix_compute);
    }, .style = S.viewport.of(.{ .max = __yix_d5: {
        const __yix_T = @TypeOf(M.maxBody(__yix_view_ctx.m.peek()));
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.maxBody(__yix_ctx.m.get());
        } }.__yix_compute);
    } }), .parts = .{ .content = .{ .style = S.content } }, }, ui.view.ref(__yix_view_ctx.viewport, __yix_builder_1711: { try ui.view.previewCheckBuilder(__yix_view_scope, W.ScrollArea); break :__yix_builder_1711 ui.view.with(W.ScrollArea(.{ .direction = .vertical, .overscroll_y = .contain, .scrollbars = .always, .scrollbar_gutter = .stable, }), .{
                    ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_interaction.yix", .path = "Interaction", .receiver = "row", .tokens = "row style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . heading ", .kind = .style, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.row(.{ .style = S.heading, }, .{
                        ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_interaction.yix", .path = "Interaction", .receiver = "icon", .tokens = "icon src = M . glyph ( \"shield-alert\" ) ; style = @static; visible = ! M . isQuestion ( m ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "src", .tokens = "M . glyph ( \"shield-alert\" ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . warn_glyph ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "! M . isQuestion ( m ) ", .kind = .property, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.icon(.{ .style = S.warn_glyph, .visible = __yix_d8: {
        const __yix_T = @TypeOf(!M.isQuestion(__yix_view_ctx.m.peek()));
        break :__yix_d8 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return !M.isQuestion(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }, __yix_call7: {
        const __yix_Raw = @TypeOf(M.glyph("shield-alert"));
        break :__yix_call7 if (comptime !ui.view.yixCallMayDerive(__yix_Raw)) M.glyph("shield-alert") else __yix_d6: {
        const __yix_T = @TypeOf(M.glyph("shield-alert"));
        break :__yix_d6 try __yix_view_scope.derive(__yix_T, .{ }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            _ = __yix_ctx;
            return M.glyph("shield-alert");
        } }.__yix_compute);
    };
    })),
                        ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_interaction.yix", .path = "Interaction", .receiver = "icon", .tokens = "icon src = M . glyph ( \"message-circle-question\" ) ; style = @static; visible = M . isQuestion ( m ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "src", .tokens = "M . glyph ( \"message-circle-question\" ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . ask_glyph ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "M . isQuestion ( m ) ", .kind = .property, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.icon(.{ .style = S.ask_glyph, .visible = __yix_d11: {
        const __yix_T = @TypeOf(M.isQuestion(__yix_view_ctx.m.peek()));
        break :__yix_d11 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.isQuestion(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }, __yix_call10: {
        const __yix_Raw = @TypeOf(M.glyph("message-circle-question"));
        break :__yix_call10 if (comptime !ui.view.yixCallMayDerive(__yix_Raw)) M.glyph("message-circle-question") else __yix_d9: {
        const __yix_T = @TypeOf(M.glyph("message-circle-question"));
        break :__yix_d9 try __yix_view_scope.derive(__yix_T, .{ }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            _ = __yix_ctx;
            return M.glyph("message-circle-question");
        } }.__yix_compute);
    };
    })),
                        ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_interaction.yix", .path = "Interaction", .receiver = "col", .tokens = "col style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . title_block ", .kind = .style, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.col(.{ .style = S.title_block, }, .{
                            ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_interaction.yix", .path = "Interaction", .receiver = "text", .tokens = "text testId = m . space . id ( \"ai.interaction.title\" ) ; style = @static; box = S . fill_text ; M . title ( m )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "m . space . id ( \"ai.interaction.title\" ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . title ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . fill_text ", .kind = .property, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.text(.{ .test_id = __yix_d12: {
        const __yix_T = @TypeOf(__yix_view_ctx.m.peek().space.id("ai.interaction.title"));
        break :__yix_d12 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.interaction.title");
        } }.__yix_compute);
    }, .style = S.title, .box = S.fill_text, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d13: {
        const __yix_T = @TypeOf(M.title(__yix_view_ctx.m.peek()));
        break :__yix_d13 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.title(__yix_ctx.m.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d13: {
        const __yix_T = @TypeOf(M.title(__yix_view_ctx.m.peek()));
        break :__yix_d13 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.title(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }))),
                            ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_interaction.yix", .path = "Interaction", .receiver = "text", .tokens = "text testId = m . space . id ( \"ai.interaction.target\" ) ; style = @static; box = S . fill_text ; visible = M . targetShown ( m ) ; M . target ( m )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "m . space . id ( \"ai.interaction.target\" ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . secondary ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . fill_text ", .kind = .property, .literal = null }, .{ .name = "visible", .tokens = "M . targetShown ( m ) ", .kind = .property, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.text(.{ .test_id = __yix_d14: {
        const __yix_T = @TypeOf(__yix_view_ctx.m.peek().space.id("ai.interaction.target"));
        break :__yix_d14 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.interaction.target");
        } }.__yix_compute);
    }, .style = S.secondary, .box = S.fill_text, .visible = __yix_d15: {
        const __yix_T = @TypeOf(M.targetShown(__yix_view_ctx.m.peek()));
        break :__yix_d15 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.targetShown(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d16: {
        const __yix_T = @TypeOf(M.target(__yix_view_ctx.m.peek()));
        break :__yix_d16 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.target(__yix_ctx.m.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d16: {
        const __yix_T = @TypeOf(M.target(__yix_view_ctx.m.peek()));
        break :__yix_d16 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.target(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }))),
                        })),
                    })),
                    ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_interaction.yix", .path = "Interaction", .receiver = "row", .tokens = "row style = @static; visible = M . commandShown ( m ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . command_row ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "M . commandShown ( m ) ", .kind = .property, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.row(.{ .style = S.command_row, .visible = __yix_d17: {
        const __yix_T = @TypeOf(M.commandShown(__yix_view_ctx.m.peek()));
        break :__yix_d17 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.commandShown(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }, .{
                        ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_interaction.yix", .path = "Interaction", .receiver = "text", .tokens = "text testId = m . space . id ( \"ai.interaction.command\" ) ; style = @static; box = S . command_well ; M . detail ( m )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "m . space . id ( \"ai.interaction.command\" ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . command ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . command_well ", .kind = .property, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.text(.{ .test_id = __yix_d18: {
        const __yix_T = @TypeOf(__yix_view_ctx.m.peek().space.id("ai.interaction.command"));
        break :__yix_d18 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.interaction.command");
        } }.__yix_compute);
    }, .style = S.command, .box = S.command_well, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d19: {
        const __yix_T = @TypeOf(M.detail(__yix_view_ctx.m.peek()));
        break :__yix_d19 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.detail(__yix_ctx.m.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d19: {
        const __yix_T = @TypeOf(M.detail(__yix_view_ctx.m.peek()));
        break :__yix_d19 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.detail(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }))),
                        ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_interaction.yix", .path = "Interaction", .receiver = "W.Tooltip", .tokens = "< W . Tooltip text = \"复制命令或详情\" position = { . top } > < W . Button testId = { m . space . id ( \"ai.interaction.copy\" ) } variant = { . ghost } size = { . sm } iconOnly = { true } iconAsset = { M . glyph ( \"copy\" ) } a11yLabel = \"复制命令或详情\" onClick = { M . copyDetail ( m ) } / > < / W . Tooltip > ", .literal_text = null, .attributes = &.{ .{ .name = "text", .tokens = "\"复制命令或详情\" ", .kind = .property, .literal = .{ .text = "复制命令或详情" } }, .{ .name = "position", .tokens = ". top ", .kind = .property, .literal = .{ .enum_name = "top" } }, } }, .{ .m = __yix_view_ctx.m, }, __yix_builder_2891: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Tooltip); break :__yix_builder_2891 ui.view.with(W.Tooltip(.{ .text = "复制命令或详情", .position = .top, }), .{
                            ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_interaction.yix", .path = "Interaction", .receiver = "W.Button", .tokens = "< W . Button testId = { m . space . id ( \"ai.interaction.copy\" ) } variant = { . ghost } size = { . sm } iconOnly = { true } iconAsset = { M . glyph ( \"copy\" ) } a11yLabel = \"复制命令或详情\" onClick = { M . copyDetail ( m ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "m . space . id ( \"ai.interaction.copy\" ) ", .kind = .property, .literal = null }, .{ .name = "variant", .tokens = ". ghost ", .kind = .property, .literal = .{ .enum_name = "ghost" } }, .{ .name = "size", .tokens = ". sm ", .kind = .property, .literal = .{ .enum_name = "sm" } }, .{ .name = "icon_only", .tokens = "true ", .kind = .property, .literal = .{ .boolean = true } }, .{ .name = "icon_asset", .tokens = "M . glyph ( \"copy\" ) ", .kind = .property, .literal = null }, .{ .name = "a11y_label", .tokens = "\"复制命令或详情\" ", .kind = .property, .literal = .{ .text = "复制命令或详情" } }, .{ .name = "on_click", .tokens = "M . copyDetail ( m ) ", .kind = .event, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.templateAttrs(.{ .test_id = __yix_d20: {
        const __yix_T = if (ui.view.attrType(W.Button, "test_id")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.m.peek().space.id("ai.interaction.copy"));
        break :__yix_d20 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.interaction.copy");
        } }.__yix_compute);
    }, }, __yix_builder_2976: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_2976 W.Button(.{ .variant = .ghost, .size = .sm, .icon_only = true, .icon_asset = __yix_call22: {
        const __yix_Raw = @TypeOf(M.glyph("copy"));
        break :__yix_call22 if (comptime !ui.view.yixCallMayDerive(__yix_Raw)) M.glyph("copy") else __yix_d21: {
        const __yix_T = if (ui.view.attrType(W.Button, "icon_asset")) |__yix_A| __yix_A else @TypeOf(M.glyph("copy"));
        break :__yix_d21 try __yix_view_scope.derive(__yix_T, .{ }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            _ = __yix_ctx;
            return M.glyph("copy");
        } }.__yix_compute);
    };
    }, .a11y_label = "复制命令或详情", .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .m = __yix_view_ctx.m, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); M.copyDetail(__yix_ctx.m.peek());  } }.__yix_run) else __yix_d23: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(M.copyDetail(__yix_view_ctx.m.peek()));
        break :__yix_d23 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.copyDetail(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }); })),
                        }); }),
                    })),
                    ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_interaction.yix", .path = "Interaction", .receiver = "row", .tokens = "row testId = m . space . id ( \"ai.interaction.impact.note\" ) ; style = @static; visible = M . impactShown ( m ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "m . space . id ( \"ai.interaction.impact.note\" ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . impact_row ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "M . impactShown ( m ) ", .kind = .property, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.row(.{ .test_id = __yix_d24: {
        const __yix_T = @TypeOf(__yix_view_ctx.m.peek().space.id("ai.interaction.impact.note"));
        break :__yix_d24 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.interaction.impact.note");
        } }.__yix_compute);
    }, .style = S.impact_row, .visible = __yix_d25: {
        const __yix_T = @TypeOf(M.impactShown(__yix_view_ctx.m.peek()));
        break :__yix_d25 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.impactShown(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }, .{
                        ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_interaction.yix", .path = "Interaction", .receiver = "icon", .tokens = "icon src = M . glyph ( \"info\" ) ; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "src", .tokens = "M . glyph ( \"info\" ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . info_glyph ", .kind = .style, .literal = null }, } }, .{ }, ui.view.icon(.{ .style = S.info_glyph, }, __yix_call27: {
        const __yix_Raw = @TypeOf(M.glyph("info"));
        break :__yix_call27 if (comptime !ui.view.yixCallMayDerive(__yix_Raw)) M.glyph("info") else __yix_d26: {
        const __yix_T = @TypeOf(M.glyph("info"));
        break :__yix_d26 try __yix_view_scope.derive(__yix_T, .{ }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            _ = __yix_ctx;
            return M.glyph("info");
        } }.__yix_compute);
    };
    })),
                        ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_interaction.yix", .path = "Interaction", .receiver = "text", .tokens = "text testId = m . space . id ( \"ai.interaction.impact\" ) ; style = @static; box = S . row_text ; M . impact ( m )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "m . space . id ( \"ai.interaction.impact\" ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . secondary ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . row_text ", .kind = .property, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.text(.{ .test_id = __yix_d28: {
        const __yix_T = @TypeOf(__yix_view_ctx.m.peek().space.id("ai.interaction.impact"));
        break :__yix_d28 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.interaction.impact");
        } }.__yix_compute);
    }, .style = S.secondary, .box = S.row_text, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d29: {
        const __yix_T = @TypeOf(M.impact(__yix_view_ctx.m.peek()));
        break :__yix_d29 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.impact(__yix_ctx.m.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d29: {
        const __yix_T = @TypeOf(M.impact(__yix_view_ctx.m.peek()));
        break :__yix_d29 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.impact(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }))),
                    })),
                    ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_interaction.yix", .path = "Interaction", .receiver = "W.Tabs", .tokens = "< W . Tabs testId = { m . space . id ( \"ai.interaction.route\" ) } items = { M . routeItems ( m ) } variant = { . segmented } size = { . sm } active = { M . routeActive ( m ) } onChange = { | id | M . chooseRoute ( m , id ) } visible = { M . routeShown ( m ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "m . space . id ( \"ai.interaction.route\" ) ", .kind = .property, .literal = null }, .{ .name = "items", .tokens = "M . routeItems ( m ) ", .kind = .property, .literal = null }, .{ .name = "variant", .tokens = ". segmented ", .kind = .property, .literal = .{ .enum_name = "segmented" } }, .{ .name = "size", .tokens = ". sm ", .kind = .property, .literal = .{ .enum_name = "sm" } }, .{ .name = "active", .tokens = "M . routeActive ( m ) ", .kind = .property, .literal = null }, .{ .name = "on_change", .tokens = "| id | M . chooseRoute ( m , id ) ", .kind = .event, .literal = null }, .{ .name = "visible", .tokens = "M . routeShown ( m ) ", .kind = .property, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.templateAttrs(.{ .test_id = __yix_d30: {
        const __yix_T = if (ui.view.attrType(W.Tabs, "test_id")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.m.peek().space.id("ai.interaction.route"));
        break :__yix_d30 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.interaction.route");
        } }.__yix_compute);
    }, .visible = __yix_d33: {
        const __yix_T = if (ui.view.attrType(W.Tabs, "visible")) |__yix_A| __yix_A else @TypeOf(M.routeShown(__yix_view_ctx.m.peek()));
        break :__yix_d33 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.routeShown(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }, __yix_builder_3608: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Tabs); break :__yix_builder_3608 W.Tabs(.{ .items = __yix_d31: {
        const __yix_T = if (ui.view.attrType(W.Tabs, "items")) |__yix_A| __yix_A else @TypeOf(M.routeItems(__yix_view_ctx.m.peek()));
        break :__yix_d31 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.routeItems(__yix_ctx.m.get());
        } }.__yix_compute);
    }, .variant = .segmented, .size = .sm, .active = __yix_d32: {
        const __yix_T = if (ui.view.attrType(W.Tabs, "active")) |__yix_A| __yix_A else @TypeOf(M.routeActive(__yix_view_ctx.m.peek()));
        break :__yix_d32 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.routeActive(__yix_ctx.m.get());
        } }.__yix_compute);
    }, .on_change = ui.view.eventProp(W.Tabs, "on_change", try ui.on.bindAny(__yix_view_scope, .{ .m = __yix_view_ctx.m, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype, id: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); M.chooseRoute(__yix_ctx.m.peek(), id);  } }.__yix_run)), }); })),
                    ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_interaction.yix", .path = "Interaction", .receiver = "text", .tokens = "text style = @static; box = S . fill_text ; visible = M . reasonShown ( m ) ; M . routeReason ( m )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . reason ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . fill_text ", .kind = .property, .literal = null }, .{ .name = "visible", .tokens = "M . reasonShown ( m ) ", .kind = .property, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.text(.{ .style = S.reason, .box = S.fill_text, .visible = __yix_d34: {
        const __yix_T = @TypeOf(M.reasonShown(__yix_view_ctx.m.peek()));
        break :__yix_d34 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.reasonShown(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d35: {
        const __yix_T = @TypeOf(M.routeReason(__yix_view_ctx.m.peek()));
        break :__yix_d35 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.routeReason(__yix_ctx.m.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d35: {
        const __yix_T = @TypeOf(M.routeReason(__yix_view_ctx.m.peek()));
        break :__yix_d35 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.routeReason(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }))),
                    ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_interaction.yix", .path = "Interaction", .receiver = "col", .tokens = "col style = @static; visible = M . optionsShown ( m ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . options ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "M . optionsShown ( m ) ", .kind = .property, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.col(.{ .style = S.options, .visible = __yix_d36: {
        const __yix_T = @TypeOf(M.optionsShown(__yix_view_ctx.m.peek()));
        break :__yix_d36 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.optionsShown(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }, .{
                        ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_interaction.yix", .path = "Interaction", .receiver = "W.RadioGroup", .tokens = "< W . RadioGroup options = { M . radioOptions ( m ) } value = { M . selectedValue ( m ) } disabled = { M . locked ( m ) } onChange = { | v | M . selectionChanged ( m , v ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "options", .tokens = "M . radioOptions ( m ) ", .kind = .property, .literal = null }, .{ .name = "value", .tokens = "M . selectedValue ( m ) ", .kind = .property, .literal = null }, .{ .name = "disabled", .tokens = "M . locked ( m ) ", .kind = .property, .literal = null }, .{ .name = "on_change", .tokens = "| v | M . selectionChanged ( m , v ) ", .kind = .event, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, __yix_builder_4018: { try ui.view.previewCheckBuilder(__yix_view_scope, W.RadioGroup); break :__yix_builder_4018 W.RadioGroup(.{ .options = __yix_d37: {
        const __yix_T = if (ui.view.attrType(W.RadioGroup, "options")) |__yix_A| __yix_A else @TypeOf(M.radioOptions(__yix_view_ctx.m.peek()));
        break :__yix_d37 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.radioOptions(__yix_ctx.m.get());
        } }.__yix_compute);
    }, .value = __yix_d38: {
        const __yix_T = if (ui.view.attrType(W.RadioGroup, "value")) |__yix_A| __yix_A else @TypeOf(M.selectedValue(__yix_view_ctx.m.peek()));
        break :__yix_d38 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.selectedValue(__yix_ctx.m.get());
        } }.__yix_compute);
    }, .disabled = __yix_d39: {
        const __yix_T = if (ui.view.attrType(W.RadioGroup, "disabled")) |__yix_A| __yix_A else @TypeOf(M.locked(__yix_view_ctx.m.peek()));
        break :__yix_d39 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.locked(__yix_ctx.m.get());
        } }.__yix_compute);
    }, .on_change = ui.view.eventProp(W.RadioGroup, "on_change", try ui.on.bindAny(__yix_view_scope, .{ .m = __yix_view_ctx.m, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype, v: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); M.selectionChanged(__yix_ctx.m.peek(), v);  } }.__yix_run)), }); }),
                    })),
                    ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_interaction.yix", .path = "Interaction", .receiver = "row", .tokens = "row testId = m . space . id ( \"ai.interaction.custom\" ) ; style = @static; visible = M . customShown ( m ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "m . space . id ( \"ai.interaction.custom\" ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . custom_row ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "M . customShown ( m ) ", .kind = .property, .literal = null }, } }, .{ .m = __yix_view_ctx.m, .answer = __yix_view_ctx.answer, }, ui.view.row(.{ .test_id = __yix_d40: {
        const __yix_T = @TypeOf(__yix_view_ctx.m.peek().space.id("ai.interaction.custom"));
        break :__yix_d40 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.interaction.custom");
        } }.__yix_compute);
    }, .style = S.custom_row, .visible = __yix_d41: {
        const __yix_T = @TypeOf(M.customShown(__yix_view_ctx.m.peek()));
        break :__yix_d41 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.customShown(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }, .{
                        ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_interaction.yix", .path = "Interaction", .receiver = "W.Input", .tokens = "< W . Input ref = { answer } value = { M . customText ( m ) } placeholder = \"输入你的答案…\" size = { . sm } disabled = { M . locked ( m ) } focusId = \"ai.interaction.answer\" parts = { . { . input_container = m . space . id ( \"ai.interaction.answer\" ) } } onChange = { | t | M . customChanged ( m , t ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "ref", .tokens = "answer ", .kind = .reference, .literal = null }, .{ .name = "value", .tokens = "M . customText ( m ) ", .kind = .property, .literal = null }, .{ .name = "placeholder", .tokens = "\"输入你的答案…\" ", .kind = .property, .literal = .{ .text = "输入你的答案…" } }, .{ .name = "size", .tokens = ". sm ", .kind = .property, .literal = .{ .enum_name = "sm" } }, .{ .name = "disabled", .tokens = "M . locked ( m ) ", .kind = .property, .literal = null }, .{ .name = "focus_id", .tokens = "\"ai.interaction.answer\" ", .kind = .property, .literal = .{ .text = "ai.interaction.answer" } }, .{ .name = "parts", .tokens = ". { . input_container = m . space . id ( \"ai.interaction.answer\" ) } ", .kind = .property, .literal = null }, .{ .name = "on_change", .tokens = "| t | M . customChanged ( m , t ) ", .kind = .event, .literal = null }, } }, .{ .m = __yix_view_ctx.m, .answer = __yix_view_ctx.answer, }, ui.view.templateAttrs(.{ .focus_id = "ai.interaction.answer", .parts = .{ .input_container = __yix_d44: {
        const __yix_T = @TypeOf(__yix_view_ctx.m.peek().space.id("ai.interaction.answer"));
        break :__yix_d44 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.interaction.answer");
        } }.__yix_compute);
    } }, }, ui.view.ref(__yix_view_ctx.answer, __yix_builder_4323: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Input); break :__yix_builder_4323 W.Input(.{ .value = __yix_d42: {
        const __yix_T = if (ui.view.attrType(W.Input, "value")) |__yix_A| __yix_A else @TypeOf(M.customText(__yix_view_ctx.m.peek()));
        break :__yix_d42 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.customText(__yix_ctx.m.get());
        } }.__yix_compute);
    }, .placeholder = "输入你的答案…", .size = .sm, .disabled = __yix_d43: {
        const __yix_T = if (ui.view.attrType(W.Input, "disabled")) |__yix_A| __yix_A else @TypeOf(M.locked(__yix_view_ctx.m.peek()));
        break :__yix_d43 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.locked(__yix_ctx.m.get());
        } }.__yix_compute);
    }, .on_change = ui.view.eventProp(W.Input, "on_change", try ui.on.bindAny(__yix_view_scope, .{ .m = __yix_view_ctx.m, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype, t: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); M.customChanged(__yix_ctx.m.peek(), t);  } }.__yix_run)), }); }))),
                    })),
                    ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_interaction.yix", .path = "Interaction", .receiver = "text", .tokens = "text testId = m . space . id ( \"ai.interaction.error\" ) ; style = @static; box = S . fill_text ; visible = M . errorShown ( m ) ; M . errorText ( m )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "m . space . id ( \"ai.interaction.error\" ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . failure ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . fill_text ", .kind = .property, .literal = null }, .{ .name = "visible", .tokens = "M . errorShown ( m ) ", .kind = .property, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.text(.{ .test_id = __yix_d45: {
        const __yix_T = @TypeOf(__yix_view_ctx.m.peek().space.id("ai.interaction.error"));
        break :__yix_d45 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.interaction.error");
        } }.__yix_compute);
    }, .style = S.failure, .box = S.fill_text, .visible = __yix_d46: {
        const __yix_T = @TypeOf(M.errorShown(__yix_view_ctx.m.peek()));
        break :__yix_d46 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.errorShown(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d47: {
        const __yix_T = @TypeOf(M.errorText(__yix_view_ctx.m.peek()));
        break :__yix_d47 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.errorText(__yix_ctx.m.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d47: {
        const __yix_T = @TypeOf(M.errorText(__yix_view_ctx.m.peek()));
        break :__yix_d47 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.errorText(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }))),
                }); }))),
                ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_interaction.yix", .path = "Interaction", .receiver = "row", .tokens = "row testId = m . space . id ( \"ai.interaction.actions\" ) ; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "m . space . id ( \"ai.interaction.actions\" ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . actions ", .kind = .style, .literal = null }, } }, .{ .m = __yix_view_ctx.m, .reject = __yix_view_ctx.reject, .accept = __yix_view_ctx.accept, .submit = __yix_view_ctx.submit, }, ui.view.row(.{ .test_id = __yix_d48: {
        const __yix_T = @TypeOf(__yix_view_ctx.m.peek().space.id("ai.interaction.actions"));
        break :__yix_d48 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.interaction.actions");
        } }.__yix_compute);
    }, .style = S.actions, }, .{
                    ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_interaction.yix", .path = "Interaction", .receiver = "spacer", .tokens = "spacer ", .literal_text = null, .attributes = &.{ } }, .{ }, ui.view.spacer()),
                    ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_interaction.yix", .path = "Interaction", .receiver = "W.Button", .tokens = "< W . Button testId = { m . space . id ( \"ai.interaction.postpone\" ) } label = \"稍后处理\" variant = { . ghost } size = { . sm } disabled = { M . locked ( m ) } onClick = { M . postpone ( m ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "m . space . id ( \"ai.interaction.postpone\" ) ", .kind = .property, .literal = null }, .{ .name = "label", .tokens = "\"稍后处理\" ", .kind = .property, .literal = .{ .text = "稍后处理" } }, .{ .name = "variant", .tokens = ". ghost ", .kind = .property, .literal = .{ .enum_name = "ghost" } }, .{ .name = "size", .tokens = ". sm ", .kind = .property, .literal = .{ .enum_name = "sm" } }, .{ .name = "disabled", .tokens = "M . locked ( m ) ", .kind = .property, .literal = null }, .{ .name = "on_click", .tokens = "M . postpone ( m ) ", .kind = .event, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.templateAttrs(.{ .test_id = __yix_d49: {
        const __yix_T = if (ui.view.attrType(W.Button, "test_id")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.m.peek().space.id("ai.interaction.postpone"));
        break :__yix_d49 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.interaction.postpone");
        } }.__yix_compute);
    }, }, __yix_builder_4931: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_4931 W.Button(.{ .label = "稍后处理", .variant = .ghost, .size = .sm, .disabled = __yix_d50: {
        const __yix_T = if (ui.view.attrType(W.Button, "disabled")) |__yix_A| __yix_A else @TypeOf(M.locked(__yix_view_ctx.m.peek()));
        break :__yix_d50 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.locked(__yix_ctx.m.get());
        } }.__yix_compute);
    }, .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .m = __yix_view_ctx.m, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); M.postpone(__yix_ctx.m.peek());  } }.__yix_run) else __yix_d51: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(M.postpone(__yix_view_ctx.m.peek()));
        break :__yix_d51 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.postpone(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }); })),
                    ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_interaction.yix", .path = "Interaction", .receiver = "W.Button", .tokens = "< W . Button ref = { reject } testId = { m . space . id ( \"ai.interaction.reject\" ) } label = \"拒绝\" iconAsset = { M . glyph ( \"x\" ) } variant = { . secondary } size = { . sm } disabled = { M . locked ( m ) } visible = { ! M . isQuestion ( m ) } onClick = { M . deny ( m ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "ref", .tokens = "reject ", .kind = .reference, .literal = null }, .{ .name = "test_id", .tokens = "m . space . id ( \"ai.interaction.reject\" ) ", .kind = .property, .literal = null }, .{ .name = "label", .tokens = "\"拒绝\" ", .kind = .property, .literal = .{ .text = "拒绝" } }, .{ .name = "icon_asset", .tokens = "M . glyph ( \"x\" ) ", .kind = .property, .literal = null }, .{ .name = "variant", .tokens = ". secondary ", .kind = .property, .literal = .{ .enum_name = "secondary" } }, .{ .name = "size", .tokens = ". sm ", .kind = .property, .literal = .{ .enum_name = "sm" } }, .{ .name = "disabled", .tokens = "M . locked ( m ) ", .kind = .property, .literal = null }, .{ .name = "visible", .tokens = "! M . isQuestion ( m ) ", .kind = .property, .literal = null }, .{ .name = "on_click", .tokens = "M . deny ( m ) ", .kind = .event, .literal = null }, } }, .{ .m = __yix_view_ctx.m, .reject = __yix_view_ctx.reject, }, ui.view.templateAttrs(.{ .test_id = __yix_d52: {
        const __yix_T = if (ui.view.attrType(W.Button, "test_id")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.m.peek().space.id("ai.interaction.reject"));
        break :__yix_d52 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.interaction.reject");
        } }.__yix_compute);
    }, .visible = __yix_d56: {
        const __yix_T = if (ui.view.attrType(W.Button, "visible")) |__yix_A| __yix_A else @TypeOf(!M.isQuestion(__yix_view_ctx.m.peek()));
        break :__yix_d56 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return !M.isQuestion(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }, ui.view.ref(__yix_view_ctx.reject, __yix_builder_5107: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_5107 W.Button(.{ .label = "拒绝", .icon_asset = __yix_call54: {
        const __yix_Raw = @TypeOf(M.glyph("x"));
        break :__yix_call54 if (comptime !ui.view.yixCallMayDerive(__yix_Raw)) M.glyph("x") else __yix_d53: {
        const __yix_T = if (ui.view.attrType(W.Button, "icon_asset")) |__yix_A| __yix_A else @TypeOf(M.glyph("x"));
        break :__yix_d53 try __yix_view_scope.derive(__yix_T, .{ }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            _ = __yix_ctx;
            return M.glyph("x");
        } }.__yix_compute);
    };
    }, .variant = .secondary, .size = .sm, .disabled = __yix_d55: {
        const __yix_T = if (ui.view.attrType(W.Button, "disabled")) |__yix_A| __yix_A else @TypeOf(M.locked(__yix_view_ctx.m.peek()));
        break :__yix_d55 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.locked(__yix_ctx.m.get());
        } }.__yix_compute);
    }, .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .m = __yix_view_ctx.m, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); M.deny(__yix_ctx.m.peek());  } }.__yix_run) else __yix_d57: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(M.deny(__yix_view_ctx.m.peek()));
        break :__yix_d57 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.deny(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }); }))),
                    ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_interaction.yix", .path = "Interaction", .receiver = "W.Button", .tokens = "< W . Button ref = { accept } testId = { m . space . id ( \"ai.interaction.approve\" ) } label = \"允许执行\" iconAsset = { M . glyph ( \"check\" ) } variant = { . primary } size = { . sm } disabled = { M . locked ( m ) } visible = { ! M . isQuestion ( m ) } onClick = { M . approve ( m ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "ref", .tokens = "accept ", .kind = .reference, .literal = null }, .{ .name = "test_id", .tokens = "m . space . id ( \"ai.interaction.approve\" ) ", .kind = .property, .literal = null }, .{ .name = "label", .tokens = "\"允许执行\" ", .kind = .property, .literal = .{ .text = "允许执行" } }, .{ .name = "icon_asset", .tokens = "M . glyph ( \"check\" ) ", .kind = .property, .literal = null }, .{ .name = "variant", .tokens = ". primary ", .kind = .property, .literal = .{ .enum_name = "primary" } }, .{ .name = "size", .tokens = ". sm ", .kind = .property, .literal = .{ .enum_name = "sm" } }, .{ .name = "disabled", .tokens = "M . locked ( m ) ", .kind = .property, .literal = null }, .{ .name = "visible", .tokens = "! M . isQuestion ( m ) ", .kind = .property, .literal = null }, .{ .name = "on_click", .tokens = "M . approve ( m ) ", .kind = .event, .literal = null }, } }, .{ .m = __yix_view_ctx.m, .accept = __yix_view_ctx.accept, }, ui.view.templateAttrs(.{ .test_id = __yix_d58: {
        const __yix_T = if (ui.view.attrType(W.Button, "test_id")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.m.peek().space.id("ai.interaction.approve"));
        break :__yix_d58 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.interaction.approve");
        } }.__yix_compute);
    }, .visible = __yix_d62: {
        const __yix_T = if (ui.view.attrType(W.Button, "visible")) |__yix_A| __yix_A else @TypeOf(!M.isQuestion(__yix_view_ctx.m.peek()));
        break :__yix_d62 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return !M.isQuestion(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }, ui.view.ref(__yix_view_ctx.accept, __yix_builder_5340: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_5340 W.Button(.{ .label = "允许执行", .icon_asset = __yix_call60: {
        const __yix_Raw = @TypeOf(M.glyph("check"));
        break :__yix_call60 if (comptime !ui.view.yixCallMayDerive(__yix_Raw)) M.glyph("check") else __yix_d59: {
        const __yix_T = if (ui.view.attrType(W.Button, "icon_asset")) |__yix_A| __yix_A else @TypeOf(M.glyph("check"));
        break :__yix_d59 try __yix_view_scope.derive(__yix_T, .{ }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            _ = __yix_ctx;
            return M.glyph("check");
        } }.__yix_compute);
    };
    }, .variant = .primary, .size = .sm, .disabled = __yix_d61: {
        const __yix_T = if (ui.view.attrType(W.Button, "disabled")) |__yix_A| __yix_A else @TypeOf(M.locked(__yix_view_ctx.m.peek()));
        break :__yix_d61 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.locked(__yix_ctx.m.get());
        } }.__yix_compute);
    }, .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .m = __yix_view_ctx.m, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); M.approve(__yix_ctx.m.peek());  } }.__yix_run) else __yix_d63: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(M.approve(__yix_view_ctx.m.peek()));
        break :__yix_d63 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.approve(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }); }))),
                    ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_interaction.yix", .path = "Interaction", .receiver = "W.Button", .tokens = "< W . Button ref = { submit } testId = { m . space . id ( \"ai.interaction.submit\" ) } label = \"提交答案\" iconAsset = { M . glyph ( \"check\" ) } variant = { . primary } size = { . sm } disabled = { M . locked ( m ) } visible = { M . isQuestion ( m ) } onClick = { M . submit ( m ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "ref", .tokens = "submit ", .kind = .reference, .literal = null }, .{ .name = "test_id", .tokens = "m . space . id ( \"ai.interaction.submit\" ) ", .kind = .property, .literal = null }, .{ .name = "label", .tokens = "\"提交答案\" ", .kind = .property, .literal = .{ .text = "提交答案" } }, .{ .name = "icon_asset", .tokens = "M . glyph ( \"check\" ) ", .kind = .property, .literal = null }, .{ .name = "variant", .tokens = ". primary ", .kind = .property, .literal = .{ .enum_name = "primary" } }, .{ .name = "size", .tokens = ". sm ", .kind = .property, .literal = .{ .enum_name = "sm" } }, .{ .name = "disabled", .tokens = "M . locked ( m ) ", .kind = .property, .literal = null }, .{ .name = "visible", .tokens = "M . isQuestion ( m ) ", .kind = .property, .literal = null }, .{ .name = "on_click", .tokens = "M . submit ( m ) ", .kind = .event, .literal = null }, } }, .{ .m = __yix_view_ctx.m, .submit = __yix_view_ctx.submit, }, ui.view.templateAttrs(.{ .test_id = __yix_d64: {
        const __yix_T = if (ui.view.attrType(W.Button, "test_id")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.m.peek().space.id("ai.interaction.submit"));
        break :__yix_d64 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.interaction.submit");
        } }.__yix_compute);
    }, .visible = __yix_d68: {
        const __yix_T = if (ui.view.attrType(W.Button, "visible")) |__yix_A| __yix_A else @TypeOf(M.isQuestion(__yix_view_ctx.m.peek()));
        break :__yix_d68 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.isQuestion(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }, ui.view.ref(__yix_view_ctx.submit, __yix_builder_5585: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_5585 W.Button(.{ .label = "提交答案", .icon_asset = __yix_call66: {
        const __yix_Raw = @TypeOf(M.glyph("check"));
        break :__yix_call66 if (comptime !ui.view.yixCallMayDerive(__yix_Raw)) M.glyph("check") else __yix_d65: {
        const __yix_T = if (ui.view.attrType(W.Button, "icon_asset")) |__yix_A| __yix_A else @TypeOf(M.glyph("check"));
        break :__yix_d65 try __yix_view_scope.derive(__yix_T, .{ }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            _ = __yix_ctx;
            return M.glyph("check");
        } }.__yix_compute);
    };
    }, .variant = .primary, .size = .sm, .disabled = __yix_d67: {
        const __yix_T = if (ui.view.attrType(W.Button, "disabled")) |__yix_A| __yix_A else @TypeOf(M.locked(__yix_view_ctx.m.peek()));
        break :__yix_d67 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.locked(__yix_ctx.m.get());
        } }.__yix_compute);
    }, .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .m = __yix_view_ctx.m, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); M.submit(__yix_ctx.m.peek());  } }.__yix_run) else __yix_d69: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(M.submit(__yix_view_ctx.m.peek()));
        break :__yix_d69 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.submit(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }); }))),
                })),
            })),
        }); })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "Interaction";
    return __yix_root;
    } }.__yix_render);
    try ui.view.runLifecycleAction(scope, "onMount", .{ .m = m, .viewport = viewport, .accept = accept, .reject = reject, .submit = submit, .answer = answer, .__yix_owner = scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { if (comptime @import("builtin").is_test) __yix_ctx.__yix_owner.recordTestHook(.onMount); __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); keep(__yix_ctx.m.peek(), __yix_ctx.viewport, __yix_ctx.accept, __yix_ctx.reject, __yix_ctx.submit, __yix_ctx.answer);  } }.__yix_run);
    return __yix_view;

}

/// “有 1 项操作待确认” / “有 1 个问题待回答”: shown after 稍后处理; a click reopens the panel. The host
/// places it (just above the composer, at its right edge).
pub fn PendingCapsule(args: anytype) ui.view.ComponentOf(__yix_PendingCapsule) {
    return ui.view.component(__yix_PendingCapsule, ui.reactive.props.coerce(PendingCapsuleProps, args));
}
pub const PendingCapsuleProps = struct {
    m: ui.Source(*M.View),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = PendingCapsule;
    pub const __yix_preview_mount = __yix_PendingCapsule;
};
fn __yix_PendingCapsule(__yix_props: PendingCapsuleProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const m = __yix_props.m;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .m = m, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_interaction.yix", .path = "PendingCapsule", .receiver = "W.Button", .tokens = "< W . Button testId = { m . space . id ( \"ai.interaction.pending\" ) } label = { M . pendingText ( m ) } variant = { . secondary } size = { . sm } iconAsset = { ui . icons . clock } a11yLabel = \"继续处理待办请求\" visible = { M . pendingShown ( m ) } onClick = { M . reopen ( m ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "m . space . id ( \"ai.interaction.pending\" ) ", .kind = .property, .literal = null }, .{ .name = "label", .tokens = "M . pendingText ( m ) ", .kind = .property, .literal = null }, .{ .name = "variant", .tokens = ". secondary ", .kind = .property, .literal = .{ .enum_name = "secondary" } }, .{ .name = "size", .tokens = ". sm ", .kind = .property, .literal = .{ .enum_name = "sm" } }, .{ .name = "icon_asset", .tokens = "ui . icons . clock ", .kind = .property, .literal = null }, .{ .name = "a11y_label", .tokens = "\"继续处理待办请求\" ", .kind = .property, .literal = .{ .text = "继续处理待办请求" } }, .{ .name = "visible", .tokens = "M . pendingShown ( m ) ", .kind = .property, .literal = null }, .{ .name = "on_click", .tokens = "M . reopen ( m ) ", .kind = .event, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .m = __yix_view_ctx.m, }, ui.view.templateAttrs(.{ .test_id = __yix_d1: {
        const __yix_T = if (ui.view.attrType(W.Button, "test_id")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.m.peek().space.id("ai.interaction.pending"));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.interaction.pending");
        } }.__yix_compute);
    }, .visible = __yix_d3: {
        const __yix_T = if (ui.view.attrType(W.Button, "visible")) |__yix_A| __yix_A else @TypeOf(M.pendingShown(__yix_view_ctx.m.peek()));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.pendingShown(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }, __yix_builder_6130: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_6130 W.Button(.{ .label = __yix_d2: {
        const __yix_T = if (ui.view.attrType(W.Button, "label")) |__yix_A| __yix_A else @TypeOf(M.pendingText(__yix_view_ctx.m.peek()));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.pendingText(__yix_ctx.m.get());
        } }.__yix_compute);
    }, .variant = .secondary, .size = .sm, .icon_asset = ui.icons.clock, .a11y_label = "继续处理待办请求", .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .m = __yix_view_ctx.m, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); M.reopen(__yix_ctx.m.peek());  } }.__yix_run) else __yix_d4: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(M.reopen(__yix_view_ctx.m.peek()));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.reopen(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }); })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "PendingCapsule";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

const __yix_preview_source: ?[]const u8 = if (ui.view.template.preview_enabled) "\x2f\x2f\x21\x20\x54\x68\x65\x20\x63\x6f\x6d\x70\x6f\x73\x65\x72\x27\x73\x20\x64\x65\x63\x69\x73\x69\x6f\x6e\x20\x70\x61\x6e\x65\x6c\x20\x28\x50\x65\x6e\x63\x69\x6c\x20\x4b\x61\x66\x37\x45\x20\x41\x37\x20\x61\x70\x70\x72\x6f\x76\x61\x6c\x20\x2f\x20\x41\x31\x31\x20\x71\x75\x65\x73\x74\x69\x6f\x6e\x29\x3a\x20\x77\x68\x69\x6c\x65\x20\x61\x20\x72\x65\x71\x75\x65\x73\x74\x20\x69\x73\x0a\x2f\x2f\x21\x20\x70\x65\x6e\x64\x69\x6e\x67\x20\x69\x74\x20\x74\x61\x6b\x65\x73\x20\x74\x68\x65\x20\x63\x6f\x6d\x70\x6f\x73\x65\x72\x27\x73\x20\x70\x6c\x61\x63\x65\x20\xe2\x80\x94\x20\x61\x20\x6e\x61\x74\x69\x76\x65\x20\x6f\x75\x74\x6c\x69\x6e\x65\x64\x20\x60\x57\x2e\x43\x61\x72\x64\x60\x20\x68\x6f\x6c\x64\x69\x6e\x67\x20\x74\x68\x65\x20\x68\x65\x61\x64\x69\x6e\x67\x2c\x20\x74\x68\x65\x0a\x2f\x2f\x21\x20\x63\x6f\x6d\x6d\x61\x6e\x64\x20\x77\x65\x6c\x6c\x20\x77\x69\x74\x68\x20\x61\x20\x63\x6f\x70\x79\x20\x60\x57\x2e\x42\x75\x74\x74\x6f\x6e\x60\x20\x28\x2b\x20\x60\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x60\x29\x2c\x20\x74\x68\x65\x20\x69\x6d\x70\x61\x63\x74\x20\x6e\x6f\x74\x65\x2c\x20\x74\x68\x65\x20\x72\x75\x6e\x2d\x6d\x6f\x64\x65\x20\x63\x68\x6f\x69\x63\x65\x0a\x2f\x2f\x21\x20\x28\x6e\x61\x74\x69\x76\x65\x20\x73\x65\x67\x6d\x65\x6e\x74\x65\x64\x20\x60\x57\x2e\x54\x61\x62\x73\x60\x20\x73\x6d\x29\x2c\x20\x74\x68\x65\x20\x71\x75\x65\x73\x74\x69\x6f\x6e\x27\x73\x20\x6e\x61\x74\x69\x76\x65\x20\x60\x57\x2e\x52\x61\x64\x69\x6f\x47\x72\x6f\x75\x70\x60\x20\x28\x2b\x20\x61\x20\x60\x57\x2e\x49\x6e\x70\x75\x74\x60\x20\x66\x6f\x72\x20\x61\x20\x63\x75\x73\x74\x6f\x6d\x0a\x2f\x2f\x21\x20\x61\x6e\x73\x77\x65\x72\x29\x20\x61\x6e\x64\x20\x74\x68\x65\x20\x61\x63\x74\x69\x6f\x6e\x20\x72\x6f\x77\x20\x28\x67\x68\x6f\x73\x74\x20\xe2\x80\x9c\xe7\xa8\x8d\xe5\x90\x8e\xe5\xa4\x84\xe7\x90\x86\xe2\x80\x9d\x2c\x20\x73\x65\x63\x6f\x6e\x64\x61\x72\x79\x20\xe2\x80\x9c\xe6\x8b\x92\xe7\xbb\x9d\xe2\x80\x9d\x2c\x20\x70\x72\x69\x6d\x61\x72\x79\x20\xe2\x80\x9c\xe5\x85\x81\xe8\xae\xb8\xe6\x89\xa7\xe8\xa1\x8c\xe2\x80\x9d\x20\x2f\x20\xe2\x80\x9c\xe6\x8f\x90\xe4\xba\xa4\xe7\xad\x94\xe6\xa1\x88\xe2\x80\x9d\x29\x2e\x0a\x2f\x2f\x21\x20\xe2\x80\x9c\xe7\xa8\x8d\xe5\x90\x8e\xe5\xa4\x84\xe7\x90\x86\xe2\x80\x9d\x20\x66\x6f\x6c\x64\x73\x20\x69\x74\x20\x69\x6e\x74\x6f\x20\x61\x20\x6e\x61\x74\x69\x76\x65\x20\x73\x65\x63\x6f\x6e\x64\x61\x72\x79\x20\x73\x6d\x20\x60\x57\x2e\x42\x75\x74\x74\x6f\x6e\x60\x20\x63\x61\x70\x73\x75\x6c\x65\x20\x61\x62\x6f\x76\x65\x20\x74\x68\x65\x20\x63\x6f\x6d\x70\x6f\x73\x65\x72\x0a\x2f\x2f\x21\x20\x28\x60\x50\x65\x6e\x64\x69\x6e\x67\x43\x61\x70\x73\x75\x6c\x65\x60\x29\x2e\x20\x53\x74\x61\x74\x65\x2c\x20\x74\x69\x63\x6b\x65\x74\x73\x20\x61\x6e\x64\x20\x64\x65\x63\x69\x73\x69\x6f\x6e\x73\x20\x6c\x69\x76\x65\x20\x69\x6e\x20\x74\x68\x65\x20\x76\x69\x65\x77\x2d\x6d\x6f\x64\x65\x6c\x0a\x2f\x2f\x21\x20\x28\x60\x61\x69\x5f\x63\x6f\x6d\x70\x6f\x73\x65\x72\x5f\x69\x6e\x74\x65\x72\x61\x63\x74\x69\x6f\x6e\x5f\x76\x69\x65\x77\x2e\x7a\x69\x67\x60\x29\x3b\x20\x74\x68\x69\x73\x20\x66\x69\x6c\x65\x20\x69\x73\x20\x74\x68\x65\x20\x76\x69\x65\x77\x20\x6f\x6e\x6c\x79\x2e\x0a\x63\x6f\x6e\x73\x74\x20\x75\x69\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x75\x69\x22\x29\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x57\x20\x3d\x20\x75\x69\x2e\x77\x69\x64\x67\x65\x74\x73\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x53\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x61\x69\x5f\x63\x6f\x6d\x70\x6f\x73\x65\x72\x5f\x69\x6e\x74\x65\x72\x61\x63\x74\x69\x6f\x6e\x2e\x79\x73\x73\x22\x29\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x4d\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x61\x69\x5f\x63\x6f\x6d\x70\x6f\x73\x65\x72\x5f\x69\x6e\x74\x65\x72\x61\x63\x74\x69\x6f\x6e\x5f\x76\x69\x65\x77\x2e\x7a\x69\x67\x22\x29\x3b\x0a\x0a\x66\x6e\x20\x6b\x65\x65\x70\x28\x6d\x3a\x20\x2a\x4d\x2e\x56\x69\x65\x77\x2c\x20\x76\x69\x65\x77\x70\x6f\x72\x74\x3a\x20\x2a\x75\x69\x2e\x76\x69\x65\x77\x2e\x52\x65\x66\x28\x57\x2e\x73\x63\x72\x6f\x6c\x6c\x5f\x61\x72\x65\x61\x2e\x53\x63\x72\x6f\x6c\x6c\x41\x72\x65\x61\x52\x65\x73\x75\x6c\x74\x29\x2c\x20\x61\x63\x63\x65\x70\x74\x3a\x20\x2a\x75\x69\x2e\x76\x69\x65\x77\x2e\x52\x65\x66\x28\x2a\x75\x69\x2e\x4e\x6f\x64\x65\x29\x2c\x20\x72\x65\x6a\x65\x63\x74\x3a\x20\x2a\x75\x69\x2e\x76\x69\x65\x77\x2e\x52\x65\x66\x28\x2a\x75\x69\x2e\x4e\x6f\x64\x65\x29\x2c\x20\x73\x75\x62\x6d\x69\x74\x3a\x20\x2a\x75\x69\x2e\x76\x69\x65\x77\x2e\x52\x65\x66\x28\x2a\x75\x69\x2e\x4e\x6f\x64\x65\x29\x2c\x20\x61\x6e\x73\x77\x65\x72\x3a\x20\x2a\x75\x69\x2e\x76\x69\x65\x77\x2e\x52\x65\x66\x28\x57\x2e\x69\x6e\x70\x75\x74\x2e\x49\x6e\x70\x75\x74\x52\x65\x73\x75\x6c\x74\x29\x29\x20\x76\x6f\x69\x64\x20\x7b\x0a\x20\x20\x20\x20\x6d\x2e\x6b\x65\x65\x70\x28\x76\x69\x65\x77\x70\x6f\x72\x74\x2e\x67\x65\x74\x28\x29\x2c\x20\x61\x63\x63\x65\x70\x74\x2e\x67\x65\x74\x28\x29\x2c\x20\x72\x65\x6a\x65\x63\x74\x2e\x67\x65\x74\x28\x29\x2c\x20\x73\x75\x62\x6d\x69\x74\x2e\x67\x65\x74\x28\x29\x2c\x20\x61\x6e\x73\x77\x65\x72\x29\x3b\x0a\x7d\x0a\x0a\x70\x75\x62\x20\x66\x6e\x20\x49\x6e\x74\x65\x72\x61\x63\x74\x69\x6f\x6e\x28\x6d\x3a\x20\x2a\x4d\x2e\x56\x69\x65\x77\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x76\x69\x65\x77\x70\x6f\x72\x74\x20\x3d\x20\x72\x65\x66\x28\x57\x2e\x73\x63\x72\x6f\x6c\x6c\x5f\x61\x72\x65\x61\x2e\x53\x63\x72\x6f\x6c\x6c\x41\x72\x65\x61\x52\x65\x73\x75\x6c\x74\x29\x3b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x61\x63\x63\x65\x70\x74\x20\x3d\x20\x72\x65\x66\x28\x29\x3b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x72\x65\x6a\x65\x63\x74\x20\x3d\x20\x72\x65\x66\x28\x29\x3b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x73\x75\x62\x6d\x69\x74\x20\x3d\x20\x72\x65\x66\x28\x29\x3b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x61\x6e\x73\x77\x65\x72\x20\x3d\x20\x72\x65\x66\x28\x57\x2e\x69\x6e\x70\x75\x74\x2e\x49\x6e\x70\x75\x74\x52\x65\x73\x75\x6c\x74\x29\x3b\x0a\x20\x20\x20\x20\x6f\x6e\x4d\x6f\x75\x6e\x74\x28\x6b\x65\x65\x70\x28\x6d\x2c\x20\x76\x69\x65\x77\x70\x6f\x72\x74\x2c\x20\x61\x63\x63\x65\x70\x74\x2c\x20\x72\x65\x6a\x65\x63\x74\x2c\x20\x73\x75\x62\x6d\x69\x74\x2c\x20\x61\x6e\x73\x77\x65\x72\x29\x29\x3b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x43\x61\x72\x64\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x69\x6e\x74\x65\x72\x61\x63\x74\x69\x6f\x6e\x2e\x63\x61\x72\x64\x22\x29\x7d\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x6f\x75\x74\x6c\x69\x6e\x65\x64\x7d\x20\x70\x61\x64\x64\x65\x64\x3d\x7b\x66\x61\x6c\x73\x65\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x4d\x2e\x65\x78\x70\x61\x6e\x64\x65\x64\x28\x6d\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x63\x6f\x6c\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x62\x6f\x64\x79\x7d\x20\x66\x6f\x63\x75\x73\x52\x65\x71\x75\x65\x73\x74\x3d\x7b\x4d\x2e\x66\x6f\x63\x75\x73\x28\x6d\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x53\x63\x72\x6f\x6c\x6c\x41\x72\x65\x61\x20\x72\x65\x66\x3d\x7b\x76\x69\x65\x77\x70\x6f\x72\x74\x7d\x20\x64\x69\x72\x65\x63\x74\x69\x6f\x6e\x3d\x7b\x2e\x76\x65\x72\x74\x69\x63\x61\x6c\x7d\x20\x6f\x76\x65\x72\x73\x63\x72\x6f\x6c\x6c\x59\x3d\x7b\x2e\x63\x6f\x6e\x74\x61\x69\x6e\x7d\x20\x73\x63\x72\x6f\x6c\x6c\x62\x61\x72\x73\x3d\x7b\x2e\x61\x6c\x77\x61\x79\x73\x7d\x20\x73\x63\x72\x6f\x6c\x6c\x62\x61\x72\x47\x75\x74\x74\x65\x72\x3d\x7b\x2e\x73\x74\x61\x62\x6c\x65\x7d\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x69\x6e\x74\x65\x72\x61\x63\x74\x69\x6f\x6e\x2e\x70\x61\x6e\x65\x6c\x22\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x76\x69\x65\x77\x70\x6f\x72\x74\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x6d\x61\x78\x20\x3d\x20\x4d\x2e\x6d\x61\x78\x42\x6f\x64\x79\x28\x6d\x29\x20\x7d\x29\x7d\x20\x70\x61\x72\x74\x73\x3d\x7b\x2e\x7b\x20\x2e\x63\x6f\x6e\x74\x65\x6e\x74\x20\x3d\x20\x2e\x7b\x20\x2e\x73\x74\x79\x6c\x65\x20\x3d\x20\x53\x2e\x63\x6f\x6e\x74\x65\x6e\x74\x20\x7d\x20\x7d\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x72\x6f\x77\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x68\x65\x61\x64\x69\x6e\x67\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x69\x63\x6f\x6e\x20\x73\x72\x63\x3d\x7b\x4d\x2e\x67\x6c\x79\x70\x68\x28\x22\x73\x68\x69\x65\x6c\x64\x2d\x61\x6c\x65\x72\x74\x22\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x77\x61\x72\x6e\x5f\x67\x6c\x79\x70\x68\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x21\x4d\x2e\x69\x73\x51\x75\x65\x73\x74\x69\x6f\x6e\x28\x6d\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x69\x63\x6f\x6e\x20\x73\x72\x63\x3d\x7b\x4d\x2e\x67\x6c\x79\x70\x68\x28\x22\x6d\x65\x73\x73\x61\x67\x65\x2d\x63\x69\x72\x63\x6c\x65\x2d\x71\x75\x65\x73\x74\x69\x6f\x6e\x22\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x61\x73\x6b\x5f\x67\x6c\x79\x70\x68\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x4d\x2e\x69\x73\x51\x75\x65\x73\x74\x69\x6f\x6e\x28\x6d\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x63\x6f\x6c\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x74\x69\x74\x6c\x65\x5f\x62\x6c\x6f\x63\x6b\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x69\x6e\x74\x65\x72\x61\x63\x74\x69\x6f\x6e\x2e\x74\x69\x74\x6c\x65\x22\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x74\x69\x74\x6c\x65\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x66\x69\x6c\x6c\x5f\x74\x65\x78\x74\x7d\x3e\x7b\x4d\x2e\x74\x69\x74\x6c\x65\x28\x6d\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x69\x6e\x74\x65\x72\x61\x63\x74\x69\x6f\x6e\x2e\x74\x61\x72\x67\x65\x74\x22\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x63\x6f\x6e\x64\x61\x72\x79\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x66\x69\x6c\x6c\x5f\x74\x65\x78\x74\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x4d\x2e\x74\x61\x72\x67\x65\x74\x53\x68\x6f\x77\x6e\x28\x6d\x29\x7d\x3e\x7b\x4d\x2e\x74\x61\x72\x67\x65\x74\x28\x6d\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x72\x6f\x77\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x72\x6f\x77\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x63\x6f\x6d\x6d\x61\x6e\x64\x5f\x72\x6f\x77\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x4d\x2e\x63\x6f\x6d\x6d\x61\x6e\x64\x53\x68\x6f\x77\x6e\x28\x6d\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x69\x6e\x74\x65\x72\x61\x63\x74\x69\x6f\x6e\x2e\x63\x6f\x6d\x6d\x61\x6e\x64\x22\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x63\x6f\x6d\x6d\x61\x6e\x64\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x63\x6f\x6d\x6d\x61\x6e\x64\x5f\x77\x65\x6c\x6c\x7d\x3e\x7b\x4d\x2e\x64\x65\x74\x61\x69\x6c\x28\x6d\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x20\x74\x65\x78\x74\x3d\x22\xe5\xa4\x8d\xe5\x88\xb6\xe5\x91\xbd\xe4\xbb\xa4\xe6\x88\x96\xe8\xaf\xa6\xe6\x83\x85\x22\x20\x70\x6f\x73\x69\x74\x69\x6f\x6e\x3d\x7b\x2e\x74\x6f\x70\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x69\x6e\x74\x65\x72\x61\x63\x74\x69\x6f\x6e\x2e\x63\x6f\x70\x79\x22\x29\x7d\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x67\x68\x6f\x73\x74\x7d\x20\x73\x69\x7a\x65\x3d\x7b\x2e\x73\x6d\x7d\x20\x69\x63\x6f\x6e\x4f\x6e\x6c\x79\x3d\x7b\x74\x72\x75\x65\x7d\x20\x69\x63\x6f\x6e\x41\x73\x73\x65\x74\x3d\x7b\x4d\x2e\x67\x6c\x79\x70\x68\x28\x22\x63\x6f\x70\x79\x22\x29\x7d\x20\x61\x31\x31\x79\x4c\x61\x62\x65\x6c\x3d\x22\xe5\xa4\x8d\xe5\x88\xb6\xe5\x91\xbd\xe4\xbb\xa4\xe6\x88\x96\xe8\xaf\xa6\xe6\x83\x85\x22\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x4d\x2e\x63\x6f\x70\x79\x44\x65\x74\x61\x69\x6c\x28\x6d\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x72\x6f\x77\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x72\x6f\x77\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x69\x6e\x74\x65\x72\x61\x63\x74\x69\x6f\x6e\x2e\x69\x6d\x70\x61\x63\x74\x2e\x6e\x6f\x74\x65\x22\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x69\x6d\x70\x61\x63\x74\x5f\x72\x6f\x77\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x4d\x2e\x69\x6d\x70\x61\x63\x74\x53\x68\x6f\x77\x6e\x28\x6d\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x69\x63\x6f\x6e\x20\x73\x72\x63\x3d\x7b\x4d\x2e\x67\x6c\x79\x70\x68\x28\x22\x69\x6e\x66\x6f\x22\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x69\x6e\x66\x6f\x5f\x67\x6c\x79\x70\x68\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x69\x6e\x74\x65\x72\x61\x63\x74\x69\x6f\x6e\x2e\x69\x6d\x70\x61\x63\x74\x22\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x63\x6f\x6e\x64\x61\x72\x79\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x72\x6f\x77\x5f\x74\x65\x78\x74\x7d\x3e\x7b\x4d\x2e\x69\x6d\x70\x61\x63\x74\x28\x6d\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x72\x6f\x77\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x54\x61\x62\x73\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x69\x6e\x74\x65\x72\x61\x63\x74\x69\x6f\x6e\x2e\x72\x6f\x75\x74\x65\x22\x29\x7d\x20\x69\x74\x65\x6d\x73\x3d\x7b\x4d\x2e\x72\x6f\x75\x74\x65\x49\x74\x65\x6d\x73\x28\x6d\x29\x7d\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x73\x65\x67\x6d\x65\x6e\x74\x65\x64\x7d\x20\x73\x69\x7a\x65\x3d\x7b\x2e\x73\x6d\x7d\x20\x61\x63\x74\x69\x76\x65\x3d\x7b\x4d\x2e\x72\x6f\x75\x74\x65\x41\x63\x74\x69\x76\x65\x28\x6d\x29\x7d\x20\x6f\x6e\x43\x68\x61\x6e\x67\x65\x3d\x7b\x7c\x69\x64\x7c\x20\x4d\x2e\x63\x68\x6f\x6f\x73\x65\x52\x6f\x75\x74\x65\x28\x6d\x2c\x20\x69\x64\x29\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x4d\x2e\x72\x6f\x75\x74\x65\x53\x68\x6f\x77\x6e\x28\x6d\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x72\x65\x61\x73\x6f\x6e\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x66\x69\x6c\x6c\x5f\x74\x65\x78\x74\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x4d\x2e\x72\x65\x61\x73\x6f\x6e\x53\x68\x6f\x77\x6e\x28\x6d\x29\x7d\x3e\x7b\x4d\x2e\x72\x6f\x75\x74\x65\x52\x65\x61\x73\x6f\x6e\x28\x6d\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x63\x6f\x6c\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6f\x70\x74\x69\x6f\x6e\x73\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x4d\x2e\x6f\x70\x74\x69\x6f\x6e\x73\x53\x68\x6f\x77\x6e\x28\x6d\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x52\x61\x64\x69\x6f\x47\x72\x6f\x75\x70\x20\x6f\x70\x74\x69\x6f\x6e\x73\x3d\x7b\x4d\x2e\x72\x61\x64\x69\x6f\x4f\x70\x74\x69\x6f\x6e\x73\x28\x6d\x29\x7d\x20\x76\x61\x6c\x75\x65\x3d\x7b\x4d\x2e\x73\x65\x6c\x65\x63\x74\x65\x64\x56\x61\x6c\x75\x65\x28\x6d\x29\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x4d\x2e\x6c\x6f\x63\x6b\x65\x64\x28\x6d\x29\x7d\x20\x6f\x6e\x43\x68\x61\x6e\x67\x65\x3d\x7b\x7c\x76\x7c\x20\x4d\x2e\x73\x65\x6c\x65\x63\x74\x69\x6f\x6e\x43\x68\x61\x6e\x67\x65\x64\x28\x6d\x2c\x20\x76\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x72\x6f\x77\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x69\x6e\x74\x65\x72\x61\x63\x74\x69\x6f\x6e\x2e\x63\x75\x73\x74\x6f\x6d\x22\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x63\x75\x73\x74\x6f\x6d\x5f\x72\x6f\x77\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x4d\x2e\x63\x75\x73\x74\x6f\x6d\x53\x68\x6f\x77\x6e\x28\x6d\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x49\x6e\x70\x75\x74\x20\x72\x65\x66\x3d\x7b\x61\x6e\x73\x77\x65\x72\x7d\x20\x76\x61\x6c\x75\x65\x3d\x7b\x4d\x2e\x63\x75\x73\x74\x6f\x6d\x54\x65\x78\x74\x28\x6d\x29\x7d\x20\x70\x6c\x61\x63\x65\x68\x6f\x6c\x64\x65\x72\x3d\x22\xe8\xbe\x93\xe5\x85\xa5\xe4\xbd\xa0\xe7\x9a\x84\xe7\xad\x94\xe6\xa1\x88\xe2\x80\xa6\x22\x20\x73\x69\x7a\x65\x3d\x7b\x2e\x73\x6d\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x4d\x2e\x6c\x6f\x63\x6b\x65\x64\x28\x6d\x29\x7d\x20\x66\x6f\x63\x75\x73\x49\x64\x3d\x22\x61\x69\x2e\x69\x6e\x74\x65\x72\x61\x63\x74\x69\x6f\x6e\x2e\x61\x6e\x73\x77\x65\x72\x22\x20\x70\x61\x72\x74\x73\x3d\x7b\x2e\x7b\x20\x2e\x69\x6e\x70\x75\x74\x5f\x63\x6f\x6e\x74\x61\x69\x6e\x65\x72\x20\x3d\x20\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x69\x6e\x74\x65\x72\x61\x63\x74\x69\x6f\x6e\x2e\x61\x6e\x73\x77\x65\x72\x22\x29\x20\x7d\x7d\x20\x6f\x6e\x43\x68\x61\x6e\x67\x65\x3d\x7b\x7c\x74\x7c\x20\x4d\x2e\x63\x75\x73\x74\x6f\x6d\x43\x68\x61\x6e\x67\x65\x64\x28\x6d\x2c\x20\x74\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x72\x6f\x77\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x69\x6e\x74\x65\x72\x61\x63\x74\x69\x6f\x6e\x2e\x65\x72\x72\x6f\x72\x22\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x66\x61\x69\x6c\x75\x72\x65\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x66\x69\x6c\x6c\x5f\x74\x65\x78\x74\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x4d\x2e\x65\x72\x72\x6f\x72\x53\x68\x6f\x77\x6e\x28\x6d\x29\x7d\x3e\x7b\x4d\x2e\x65\x72\x72\x6f\x72\x54\x65\x78\x74\x28\x6d\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x53\x63\x72\x6f\x6c\x6c\x41\x72\x65\x61\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x72\x6f\x77\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x69\x6e\x74\x65\x72\x61\x63\x74\x69\x6f\x6e\x2e\x61\x63\x74\x69\x6f\x6e\x73\x22\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x61\x63\x74\x69\x6f\x6e\x73\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x73\x70\x61\x63\x65\x72\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x69\x6e\x74\x65\x72\x61\x63\x74\x69\x6f\x6e\x2e\x70\x6f\x73\x74\x70\x6f\x6e\x65\x22\x29\x7d\x20\x6c\x61\x62\x65\x6c\x3d\x22\xe7\xa8\x8d\xe5\x90\x8e\xe5\xa4\x84\xe7\x90\x86\x22\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x67\x68\x6f\x73\x74\x7d\x20\x73\x69\x7a\x65\x3d\x7b\x2e\x73\x6d\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x4d\x2e\x6c\x6f\x63\x6b\x65\x64\x28\x6d\x29\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x4d\x2e\x70\x6f\x73\x74\x70\x6f\x6e\x65\x28\x6d\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x72\x65\x66\x3d\x7b\x72\x65\x6a\x65\x63\x74\x7d\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x69\x6e\x74\x65\x72\x61\x63\x74\x69\x6f\x6e\x2e\x72\x65\x6a\x65\x63\x74\x22\x29\x7d\x20\x6c\x61\x62\x65\x6c\x3d\x22\xe6\x8b\x92\xe7\xbb\x9d\x22\x20\x69\x63\x6f\x6e\x41\x73\x73\x65\x74\x3d\x7b\x4d\x2e\x67\x6c\x79\x70\x68\x28\x22\x78\x22\x29\x7d\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x73\x65\x63\x6f\x6e\x64\x61\x72\x79\x7d\x20\x73\x69\x7a\x65\x3d\x7b\x2e\x73\x6d\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x4d\x2e\x6c\x6f\x63\x6b\x65\x64\x28\x6d\x29\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x21\x4d\x2e\x69\x73\x51\x75\x65\x73\x74\x69\x6f\x6e\x28\x6d\x29\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x4d\x2e\x64\x65\x6e\x79\x28\x6d\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x72\x65\x66\x3d\x7b\x61\x63\x63\x65\x70\x74\x7d\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x69\x6e\x74\x65\x72\x61\x63\x74\x69\x6f\x6e\x2e\x61\x70\x70\x72\x6f\x76\x65\x22\x29\x7d\x20\x6c\x61\x62\x65\x6c\x3d\x22\xe5\x85\x81\xe8\xae\xb8\xe6\x89\xa7\xe8\xa1\x8c\x22\x20\x69\x63\x6f\x6e\x41\x73\x73\x65\x74\x3d\x7b\x4d\x2e\x67\x6c\x79\x70\x68\x28\x22\x63\x68\x65\x63\x6b\x22\x29\x7d\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x70\x72\x69\x6d\x61\x72\x79\x7d\x20\x73\x69\x7a\x65\x3d\x7b\x2e\x73\x6d\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x4d\x2e\x6c\x6f\x63\x6b\x65\x64\x28\x6d\x29\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x21\x4d\x2e\x69\x73\x51\x75\x65\x73\x74\x69\x6f\x6e\x28\x6d\x29\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x4d\x2e\x61\x70\x70\x72\x6f\x76\x65\x28\x6d\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x72\x65\x66\x3d\x7b\x73\x75\x62\x6d\x69\x74\x7d\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x69\x6e\x74\x65\x72\x61\x63\x74\x69\x6f\x6e\x2e\x73\x75\x62\x6d\x69\x74\x22\x29\x7d\x20\x6c\x61\x62\x65\x6c\x3d\x22\xe6\x8f\x90\xe4\xba\xa4\xe7\xad\x94\xe6\xa1\x88\x22\x20\x69\x63\x6f\x6e\x41\x73\x73\x65\x74\x3d\x7b\x4d\x2e\x67\x6c\x79\x70\x68\x28\x22\x63\x68\x65\x63\x6b\x22\x29\x7d\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x70\x72\x69\x6d\x61\x72\x79\x7d\x20\x73\x69\x7a\x65\x3d\x7b\x2e\x73\x6d\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x4d\x2e\x6c\x6f\x63\x6b\x65\x64\x28\x6d\x29\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x4d\x2e\x69\x73\x51\x75\x65\x73\x74\x69\x6f\x6e\x28\x6d\x29\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x4d\x2e\x73\x75\x62\x6d\x69\x74\x28\x6d\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x72\x6f\x77\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x43\x61\x72\x64\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\xe2\x80\x9c\xe6\x9c\x89\x20\x31\x20\xe9\xa1\xb9\xe6\x93\x8d\xe4\xbd\x9c\xe5\xbe\x85\xe7\xa1\xae\xe8\xae\xa4\xe2\x80\x9d\x20\x2f\x20\xe2\x80\x9c\xe6\x9c\x89\x20\x31\x20\xe4\xb8\xaa\xe9\x97\xae\xe9\xa2\x98\xe5\xbe\x85\xe5\x9b\x9e\xe7\xad\x94\xe2\x80\x9d\x3a\x20\x73\x68\x6f\x77\x6e\x20\x61\x66\x74\x65\x72\x20\xe7\xa8\x8d\xe5\x90\x8e\xe5\xa4\x84\xe7\x90\x86\x3b\x20\x61\x20\x63\x6c\x69\x63\x6b\x20\x72\x65\x6f\x70\x65\x6e\x73\x20\x74\x68\x65\x20\x70\x61\x6e\x65\x6c\x2e\x20\x54\x68\x65\x20\x68\x6f\x73\x74\x0a\x2f\x2f\x2f\x20\x70\x6c\x61\x63\x65\x73\x20\x69\x74\x20\x28\x6a\x75\x73\x74\x20\x61\x62\x6f\x76\x65\x20\x74\x68\x65\x20\x63\x6f\x6d\x70\x6f\x73\x65\x72\x2c\x20\x61\x74\x20\x69\x74\x73\x20\x72\x69\x67\x68\x74\x20\x65\x64\x67\x65\x29\x2e\x0a\x70\x75\x62\x20\x66\x6e\x20\x50\x65\x6e\x64\x69\x6e\x67\x43\x61\x70\x73\x75\x6c\x65\x28\x6d\x3a\x20\x2a\x4d\x2e\x56\x69\x65\x77\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x69\x6e\x74\x65\x72\x61\x63\x74\x69\x6f\x6e\x2e\x70\x65\x6e\x64\x69\x6e\x67\x22\x29\x7d\x20\x6c\x61\x62\x65\x6c\x3d\x7b\x4d\x2e\x70\x65\x6e\x64\x69\x6e\x67\x54\x65\x78\x74\x28\x6d\x29\x7d\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x73\x65\x63\x6f\x6e\x64\x61\x72\x79\x7d\x20\x73\x69\x7a\x65\x3d\x7b\x2e\x73\x6d\x7d\x20\x69\x63\x6f\x6e\x41\x73\x73\x65\x74\x3d\x7b\x75\x69\x2e\x69\x63\x6f\x6e\x73\x2e\x63\x6c\x6f\x63\x6b\x7d\x20\x61\x31\x31\x79\x4c\x61\x62\x65\x6c\x3d\x22\xe7\xbb\xa7\xe7\xbb\xad\xe5\xa4\x84\xe7\x90\x86\xe5\xbe\x85\xe5\x8a\x9e\xe8\xaf\xb7\xe6\xb1\x82\x22\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x4d\x2e\x70\x65\x6e\x64\x69\x6e\x67\x53\x68\x6f\x77\x6e\x28\x6d\x29\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x4d\x2e\x72\x65\x6f\x70\x65\x6e\x28\x6d\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a" else null;
const __YixStyleCatalog = if (ui.view.template.preview_enabled) ui.view.template.styleCatalog(.{ .@"S " = S, }) else void;

//# yix-map-data [[1230,1225],[67946,6072]]

//# yix-map ai_composer_interaction.yix
