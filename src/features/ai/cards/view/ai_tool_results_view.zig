//! Actual immutable tool facts, never the model's interpretation of an exec.
const std = @import("std");
const Positions = @import("../../../../ai/tool_results.zig").ScrollPositions;
const Offsets = @import("ai_card_scroll.zig").Offsets;
const RowLook = @import("_ai_step_row.yss.zig");
const ui = @import("ui");
const IdSpace = @import("../../shared/view/ai_id_space.zig").IdSpace;
const facts = @import("../../../../ai/tool_results.zig");
/// A record id (`facts.Record.test_id`) moved into the child namespace.
pub const facts_id_capacity = @typeInfo(@FieldType(facts.Record, "test_id")).array.len + IdSpace.child_extra;
const scope_mod = @import("../../../../ai/tool_scope.zig");
const S = @import("ai_tool_results_styles.zig");
const kvm_feedback = @import("../../../../ai/kvm_tool_feedback.zig");
pub fn appendForOwner(cx: *ui.Cx, scope: *ui.Scope, parent: *ui.Node, store: *facts.Store, owner: scope_mod.Owner) !void {
    return appendForOwnerWithToggle(cx, scope, parent, store, owner, null);
}
pub fn appendForOwnerWithToggle(cx: *ui.Cx, scope: *ui.Scope, parent: *ui.Node, store: *facts.Store, owner: scope_mod.Owner, on_toggle: ?ui.Handler(void)) !void {
    return appendForOwnerWithImages(cx, scope, parent, store, owner, on_toggle, null);
}
pub fn appendForOwnerWithImages(cx: *ui.Cx, scope: *ui.Scope, parent: *ui.Node, store: *facts.Store, owner: scope_mod.Owner, on_toggle: ?ui.Handler(void), app: ?*@import("zenit_app").App) !void {
    if (store.countForOwner(owner) == 0) return;
    const space = IdSpace.of(scope);
    const root = try ui.boxStyled(cx, S.list, .{});
    root.meta.ownership.meta.test_id = space.id("ai.tool.results");
    for (store.records.items) |record| if (record.owner.eql(owner)) {
        if (record.execution != null) {
            try root.appendChild(cx.allocator, try @import("ai_execution_result_view.zig").mount(cx, scope, store, record, null, on_toggle));
            continue;
        }
        const state = try State.mount(cx, scope, record);
        for (record.images) |reference| try state.appendImage(reference, app);
        state.on_toggle = on_toggle;
        try root.appendChild(cx.allocator, state.root);
    };
    try parent.appendChild(cx.allocator, root);
}
pub const State = struct {
    cx: *ui.Cx,
    /// Test-id namespace of the surface this card is mounted in (main assistant / child dialog).
    space: IdSpace,
    /// The card root's id in that namespace (the record's own id is the main-surface one).
    root_id: [facts_id_capacity]u8 = undefined,
    copy_command_feedback: *@import("../../../../shared/ui/components/copy_button/copy_button.zig").Button = undefined,
    copy_stdout_feedback: *@import("../../../../shared/ui/components/copy_button/copy_button.zig").Button = undefined,
    copy_stderr_feedback: *@import("../../../../shared/ui/components/copy_button/copy_button.zig").Button = undefined,
    scope: *ui.Scope,
    record: *facts.Record,
    on_toggle: ?ui.Handler(void) = null,
    root: *ui.Node,
    body: *ui.Node,
    body_disclosure: *@import("../../../../shared/ui/styles/layout_motion.zig").Disclosure = undefined,
    footer_disclosure: *@import("../../../../shared/ui/styles/layout_motion.zig").Disclosure = undefined,
    image_content: ?*ui.Node = null,
    footer: *ui.Node,
    identity: *ui.Node,
    metadata: *ui.Node,
    feedback: *ui.Node,
    diagnostic: ?*ui.Node = null,
    stdout_label: ?*ui.Node = null,
    stderr_label: ?*ui.Node = null,
    stdout_viewport: ?*ui.Node = null,
    stderr_viewport: ?*ui.Node = null,
    copy_stdout_button: ?*ui.Node = null,
    copy_stderr_button: ?*ui.Node = null,
    /// The wells' code (native W.CodeBlock, followed in place).
    stdout_code: *ui.Signal([]const u8) = undefined,
    stderr_code: *ui.Signal([]const u8) = undefined,
    indicator: *@import("ai_step_disclosure.zig").Indicator = undefined,
    /// The row's disclosure state (the header Pressable's `expanded`, also its accessible state).
    expanded: *ui.Signal(bool) = undefined,
    status_icon: ?*ui.Node = null,
    /// Reading positions of the body, the command and the wells (the record's, bound to the
    /// native ScrollAreas' controlled offsets).
    positions: *Offsets,
    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, record: *facts.Record) !*State {
        const positions = try Offsets.mount(cx, scope, try record.scrollPositions(cx.allocator));
        const space = IdSpace.of(scope);
        const self = try scope.createState(State, .{ .space = space, .cx = cx, .scope = scope, .record = record, .root = undefined, .body = undefined, .footer = undefined, .identity = undefined, .metadata = undefined, .feedback = undefined, .positions = positions });
        self.root = try ui.boxStyled(cx, S.card, .{});
        self.root.meta.ownership.meta.test_id = try space.rebase(&self.root_id, record.testId());
        self.expanded = try scope.createSignal(bool, record.expanded);
        const header = try @import("ai_step_disclosure.zig").header(cx, scope, space.id("ai.tool.result.header"), "展开或收起步骤", self.expanded, cx.on(State, self, toggle));
        try self.root.appendChild(cx.allocator, header);
        var all_succeeded = record.targets.len > 0;
        var unknown = record.error_status == .unknown or (record.dispatched and record.host == null and record.targets.len == 0 and record.error_status == null);
        var failed = record.error_status == .failed or record.error_status == .rejected;
        for (record.targets) |target| {
            all_succeeded = all_succeeded and target.result.status == .succeeded and target.feedback == null;
            failed = failed or target.result.status == .failed or target.result.status == .rejected;
            unknown = unknown or target.result.remote_effect_unknown or target.result.status == .unknown or !target.result.local_released;
        }
        if (record.host) |fact| {
            all_succeeded = fact.status == .succeeded;
            failed = fact.status == .failed or fact.status == .rejected;
            unknown = fact.status == .outcome_unknown or fact.receipt.remote_effect_unknown or !fact.receipt.local_released;
        }
        // Kaf7E A6: the row's status glyph (check / circle-x / ban / pending), no chevron.
        const step_visual = @import("../model/ai_step_visual.zig");
        var any_failed = record.error_status == .failed;
        var any_rejected = record.error_status == .rejected or record.decision == false;
        var any_cancelled = record.error_status == .cancelled or record.error_status == .timed_out;
        for (record.targets) |target| {
            any_failed = any_failed or target.result.status == .failed;
            any_rejected = any_rejected or target.result.status == .rejected;
            any_cancelled = any_cancelled or target.result.status == .cancelled or target.result.status == .timed_out;
        }
        if (record.host) |fact| {
            any_failed = fact.status == .failed;
            any_rejected = fact.status == .rejected;
        }
        const row_visual: step_visual.Visual = if (any_failed) step_visual.step(.failed) else if (any_rejected) step_visual.step(.rejected) else if (unknown) .{ .icon = "circle-alert", .tone = .warning } else if (any_cancelled) step_visual.step(.cancelled) else if (all_succeeded or record.total_elapsed_ms != null or !record.dispatched) step_visual.step(.succeeded) else step_visual.step(.running);
        self.indicator = try @import("ai_step_disclosure.zig").Indicator.mount(cx, scope, header, row_visual, space.id("ai.tool.result.disclosure"));
        self.status_icon = self.indicator.slot;
        const action_title = try @import("../model/ai_tool_titles.zig").action(cx.allocator, record.name, record.arguments);
        defer cx.allocator.free(action_title);
        const title = try ui.textStyled(cx, S.title, action_title);
        title.setStyleInline(cx.allocator, S.headerTitle(cx.tokens));
        title.meta.ownership.meta.test_id = space.id("ai.tool.result.title");
        try header.appendChild(cx.allocator, title);
        var summary_buffer: [128]u8 = undefined;
        const single_feedback = if (record.targets.len == 1 and record.targets[0].result.local_released) record.targets[0].feedback else null;
        const outcome = if (single_feedback) |info| info.label else if (unknown) "结果待核实" else if (record.error_status) |status| errorStatusLabel(status, record.error_code, record.name) else if (record.host == null and record.targets.len == 1) errorStatusLabel(record.targets[0].result.status, record.targets[0].result.error_code, record.name) else record.summary(&summary_buffer);
        const projection = try @import("../model/ai_tool_header_projection.zig").projectWithStatus(cx.allocator, record.name, record.command, outcome);
        defer cx.allocator.free(projection);
        const status = if (unknown or failed) try ui.textStyled(cx, S.stepError, projection) else try ui.textStyled(cx, S.stepArgs, projection);
        if (status.getText()) |value| {
            var style = value;
            style.wrap = .none;
            style.text_overflow = .ellipsis;
            status.setText(style);
        }
        status.setStyleInline(cx.allocator, S.headerSummary(cx.tokens));
        status.meta.ownership.meta.test_id = space.id("ai.tool.result.status");
        try header.appendChild(cx.allocator, status);
        var elapsed_ms: u64 = 0;
        for (record.targets) |target| elapsed_ms +|= target.result.elapsed_ms;
        elapsed_ms = record.total_elapsed_ms orelse elapsed_ms;
        var elapsed_buf: [48]u8 = undefined;
        const elapsed = if (elapsed_ms == 0) "—" else @import("../../../../shared/base/format.zig").duration(&elapsed_buf, elapsed_ms, .short);
        const elapsed_node = try ui.textStyled(cx, S.elapsed, elapsed);
        elapsed_node.setStyleInline(cx.allocator, S.elapsedSlot(cx.tokens));
        elapsed_node.meta.ownership.meta.test_id = space.id("ai.tool.result.elapsed");
        try header.appendChild(cx.allocator, elapsed_node);
        // The details keep their vertical input at either edge (a bounded reading surface inside
        // the conversation) and show their thumb while they overflow.
        const body = try ui.widgets.ScrollArea(.{ .direction = .vertical, .overscroll_y = .contain, .scrollbars = .always, .scrollbar_gutter = .stable, .scroll_y = positions.scrollY(.body), .on_scroll_y_change = positions.onY(cx, .body) }).mount(scope, cx);
        self.body = body.container;
        self.body.setStyleInline(cx.allocator, S.body(cx.tokens));
        self.body.meta.ownership.meta.test_id = space.id("ai.tool.result.details");
        body.content.setStyleInline(cx.allocator, S.content(cx.tokens));
        self.image_content = body.content;
        const tool_detail = try @import("../model/ai_tool_titles.zig").detail(cx.allocator, record.name);
        defer cx.allocator.free(tool_detail);
        const tool = try ui.textStyled(cx, S.text, tool_detail);
        tool.meta.ownership.meta.test_id = space.id("ai.tool.result.tool");
        try body.content.appendChild(cx.allocator, tool);
        self.body_disclosure = try @import("../../../../shared/ui/styles/layout_motion.zig").Disclosure.mount(cx, scope, self.body, record.expanded);
        try self.root.appendChild(cx.allocator, self.body_disclosure.root);
        const command_row = try ui.boxStyled(cx, S.commandRow, .{});
        // File contents remain in the original arguments for approval/copy.
        // History shows the target instead of laying out an entire JSON file.
        var decoded_name: [64]u8 = undefined;
        const logical_name = @import("../../../../ai/plugin_tools.zig").decodeName(&decoded_name, record.name) catch record.name;
        const file_target = if (std.mem.startsWith(u8, logical_name, "file.")) try @import("../model/ai_tool_header_projection.zig").project(cx.allocator, record.name, record.arguments) else null;
        defer if (file_target) |value| cx.allocator.free(value);
        const display_command = file_target orelse record.command;
        const command_lines = 1 + std.mem.count(u8, std.mem.trimEnd(u8, display_command, "\r\n"), "\n");
        const command_height = @max(@as(f32, 27), @as(f32, @floatFromInt(command_lines)) * 12 * 1.55 + 8);
        command_row.setStyleInline(cx.allocator, .{ .height = .{ .px = command_height } });
        try body.content.appendChild(cx.allocator, command_row);
        const command_scroll = try ui.widgets.ScrollArea(.{ .direction = .horizontal, .height = 27, .rubber_band_x = false, .scrollbars = .always, .scroll_x = positions.scrollX(.command), .on_scroll_x_change = positions.onX(cx, .command) }).mount(scope, cx);
        try followTheme(cx, scope, command_scroll.container, S.commandViewport);
        command_scroll.container.setStyleInline(cx.allocator, .{ .height = .{ .px = command_height } });
        command_scroll.content.setStyleInline(cx.allocator, S.outputContent(cx.tokens));
        const command = try ui.textStyled(cx, S.multilineOutput, display_command);
        command.setStyleInline(cx.allocator, .{ .width = .{ .px = @import("../../pane/view/ai_message_view.zig").textWidth(cx, display_command, 12, 400) }, .flex_shrink = 0 });
        command.meta.ownership.meta.test_id = space.id("ai.tool.result.command");
        try command_scroll.content.appendChild(cx.allocator, command);
        try command_row.appendChild(cx.allocator, command_scroll.container);
        const legacy = @import("../../../../ai/plugin_tools.zig").legacyName(record.name);
        self.copy_command_feedback = try @import("../../../../shared/ui/components/copy_button/copy_button.zig").Button.mount(cx, scope, .{ .variant = .ghost, .icon_only = true, .icon_asset = ui.icons.copy, .icon_size = @as(f32, 14), .a11y_label = if (legacy) "复制原始完整命令或路径" else "复制调用参数", .base_style = S.button(22), .on_click = cx.on(State, self, copyCommand) });
        const copy_command = self.copy_command_feedback.node;
        copy_command.meta.ownership.meta.test_id = space.id("ai.tool.result.copy_command");
        try command_row.appendChild(cx.allocator, copy_command);
        for (record.targets, 0..) |target, index| {
            const row = try scope.createState(Row, .{ .view = self, .index = index });
            var status_buf: [256]u8 = undefined;
            const label = try std.fmt.allocPrint(cx.allocator, "#{d} · {s} · {s}", .{ target.result.session_id, target.label, targetStatus(target, &status_buf) });
            row.label = label;
            try scope.onCleanup(Row, row, Row.cleanup);
            const id = try space.print(&row.test_id, "ai.tool.result.target.{d}", .{target.result.session_id});
            // A native Pressable (button semantics) whose content is the target row: the exact
            // Figma 16 / 186 / 6 / fill slots.
            const button = try ui.view.render(scope, cx, ui.view.attrs(.{ .test_id = id }, ui.widgets.Pressable(.{ .a11y_label = label, .look = RowLook.target_row, .on_click = cx.on(Row, row, Row.select) })));
            const contents = try ui.boxStyled(cx, S.targetRow, .{});
            try contents.appendChild(cx.allocator, try ui.iconTint(cx, if (target.result.transport == .local) ui.icons.terminal else ui.icons.server, @import("../../../../shared/ui/theme/app_theme.zig").current().fg_2, .{ .width = .{ .px = 16 }, .height = .{ .px = 16 }, .flex_shrink = 0 }));
            const name = try std.fmt.allocPrint(cx.allocator, "#{d} · {s}", .{ target.result.session_id, target.label });
            defer cx.allocator.free(name);
            const member_label = try ui.textStyled(cx, S.targetText, name);
            member_label.setStyleInline(cx.allocator, S.targetLabel(cx.tokens));
            if (target.feedback != null) member_label.setStyleInline(cx.allocator, .{ .width = .fill(), .flex = 1, .min_width = 0 });
            try contents.appendChild(cx.allocator, member_label);
            try contents.appendChild(cx.allocator, try ui.box(cx, .{ .width = .{ .px = 6 }, .height = .{ .px = 1 }, .flex_shrink = 0 }, .{}));
            const member_status = try ui.textStyled(cx, S.targetText, targetStatus(target, &status_buf));
            member_status.setStyleInline(cx.allocator, S.targetStatus(cx.tokens));
            if (target.feedback != null) member_status.setStyleInline(cx.allocator, .{ .width = .{ .fit = .{} }, .flex = 0, .flex_shrink = 0 });
            try contents.appendChild(cx.allocator, member_status);
            try button.appendChild(cx.allocator, contents);
            try body.content.appendChild(cx.allocator, button);
        }
        self.identity = try ui.textStyled(cx, S.text, "");
        self.identity.meta.ownership.meta.test_id = space.id("ai.tool.result.identity");
        try body.content.appendChild(cx.allocator, self.identity);
        self.metadata = try ui.textStyled(cx, S.text, "");
        self.metadata.meta.ownership.meta.test_id = space.id("ai.tool.result.metadata");
        try body.content.appendChild(cx.allocator, self.metadata);
        self.diagnostic = try ui.textStyled(cx, S.text, "");
        self.diagnostic.?.meta.ownership.meta.test_id = space.id("ai.tool.result.diagnostic");
        self.diagnostic.?.setDisplay(.none);
        try body.content.appendChild(cx.allocator, self.diagnostic.?);
        self.stdout_label = try ui.textStyled(cx, S.text, if (legacy) "标准输出" else "结果内容");
        self.stdout_label.?.meta.ownership.meta.test_id = space.id("ai.tool.result.output_label");
        try body.content.appendChild(cx.allocator, self.stdout_label.?);
        // Output wells: native W.CodeBlock (borderless, no header — the labels and copy buttons
        // above / below stay the card's; long lines keep their length and scroll sideways).
        self.stdout_code = try scope.createText("", .{});
        self.stderr_code = try scope.createText("", .{});
        self.stdout_viewport = try self.mountWell(body.content, self.stdout_code, .stdout, space.id("ai.tool.result.stdout_scroll"), space.id("ai.tool.result.stdout"));
        self.stderr_label = try ui.textStyled(cx, S.text, if (legacy) "错误输出" else "错误详情");
        self.stderr_label.?.meta.ownership.meta.test_id = space.id("ai.tool.result.error_label");
        try body.content.appendChild(cx.allocator, self.stderr_label.?);
        self.stderr_viewport = try self.mountWell(body.content, self.stderr_code, .stderr, space.id("ai.tool.result.stderr_scroll"), space.id("ai.tool.result.stderr"));
        self.footer = try ui.boxStyled(cx, S.footer, .{});
        self.footer_disclosure = try @import("../../../../shared/ui/styles/layout_motion.zig").Disclosure.mount(cx, scope, self.footer, record.expanded);
        try self.root.appendChild(cx.allocator, self.footer_disclosure.root);
        self.feedback = try ui.textStyled(cx, S.text, "执行结果");
        self.feedback.meta.ownership.meta.test_id = space.id("ai.tool.result.feedback");
        try self.footer.appendChild(cx.allocator, self.feedback);
        try self.footer.appendChild(cx.allocator, try ui.spacer(cx));
        self.copy_stdout_feedback = try @import("../../../../shared/ui/components/copy_button/copy_button.zig").Button.mount(cx, scope, .{ .variant = .ghost, .icon_only = true, .icon_asset = ui.icons.copy, .icon_size = @as(f32, 16), .a11y_label = if (legacy) "复制标准输出" else "复制结果内容", .base_style = S.button(26), .on_click = cx.on(State, self, copyStdout) });
        const copy_stdout = self.copy_stdout_feedback.node;
        self.copy_stdout_button = copy_stdout;
        copy_stdout.meta.ownership.meta.test_id = space.id("ai.tool.result.copy_stdout");
        try self.footer.appendChild(cx.allocator, copy_stdout);
        self.copy_stderr_feedback = try @import("../../../../shared/ui/components/copy_button/copy_button.zig").Button.mount(cx, scope, .{ .variant = .ghost, .icon_only = true, .icon_asset = ui.icons.clipboard, .icon_size = @as(f32, 16), .a11y_label = if (legacy) "复制错误输出" else "复制错误详情", .base_style = S.button(26), .on_click = cx.on(State, self, copyStderr) });
        const copy_stderr = self.copy_stderr_feedback.node;
        self.copy_stderr_button = copy_stderr;
        copy_stderr.meta.ownership.meta.test_id = space.id("ai.tool.result.copy_stderr");
        try self.footer.appendChild(cx.allocator, copy_stderr);
        try self.select(record.selected);
        self.applyExpanded();
        try @import("../../pane/view/ai_text_selection.zig").attach(cx, scope, body.content);
        return self;
    }
    pub fn appendImage(self: *State, reference: @import("../../../../ai/image_attachments.zig").ContentRef, app: ?*@import("zenit_app").App) !void {
        const content = reference.content() orelse return error.EmptyAttachmentResult;
        const preview = try self.scope.createState(ImagePreview, .{ .app = app, .reference = reference.retain() });
        try self.scope.onCleanup(ImagePreview, preview, ImagePreview.cleanup);
        const raster = try ui.boxStyled(self.cx, S.resultImage, .{});
        raster.meta.ownership.meta.test_id = self.space.id("ai.tool.result.image");
        if (app) |renderer_app| {
            preview.texture = try renderer_app.renderer.image_renderer.loadTexture(content.width, content.height, content.pixels);
            raster.setImage(.{ .texture_id = preview.texture.? });
        }
        try self.image_content.?.appendChild(self.cx.allocator, raster);
    }
    fn showDiagnostic(self: *State, info: ?kvm_feedback.Feedback) !void {
        const node = self.diagnostic.?;
        if (info) |value| {
            const text = try std.fmt.allocPrint(self.cx.allocator, "{s}\n下一步：{s}", .{ value.message, value.next_step });
            defer self.cx.allocator.free(text);
            try node.setTextContent(self.cx.allocator, text);
            node.setDisplay(.flex);
        } else node.setDisplay(.none);
    }
    pub fn select(self: *State, index: usize) !void {
        try self.showDiagnostic(null);
        if (self.record.host) |fact| {
            try self.identity.setTextContent(self.cx.allocator, "当前对话");
            const receipt = try std.fmt.allocPrint(self.cx.allocator, "操作 #{d} · {s}", .{ fact.receipt.operation_id, if (fact.receipt.local_released) "本地资源已释放" else "清理待核实" });
            defer self.cx.allocator.free(receipt);
            try self.metadata.setTextContent(self.cx.allocator, receipt);
            var summary: [128]u8 = undefined;
            try self.feedback.setTextContent(self.cx.allocator, if (!fact.receipt.local_released) "清理待核实" else if (fact.receipt.remote_effect_unknown) "执行结果待核实" else self.record.summary(&summary));
            if (fact.fetch) |feedback| {
                try self.diagnostic.?.setTextContent(self.cx.allocator, feedback.detail);
                self.diagnostic.?.setDisplay(.flex);
            }
            try self.showOutput(fact.content, "");
            return;
        }
        if (self.record.targets.len == 0) {
            try self.identity.setTextContent(self.cx.allocator, "没有已执行的目标");
            try self.metadata.setTextContent(self.cx.allocator, self.record.error_code orelse "尚未执行");
            try self.feedback.setTextContent(self.cx.allocator, if (self.record.error_status) |value| errorStatusLabel(value, self.record.error_code, self.record.name) else if (self.record.decision == false) "已拒绝" else "尚未执行");
            if (kvm_feedback.isTool(self.record.name)) {
                if (self.record.error_code) |code| try self.showDiagnostic(kvm_feedback.failure(code));
            }
            self.stdout_label.?.setDisplay(.none);
            self.stderr_label.?.setDisplay(.none);
            self.stdout_viewport.?.setDisplay(.none);
            self.stderr_viewport.?.setDisplay(.none);
            self.copy_stdout_button.?.setDisplay(.none);
            self.copy_stderr_button.?.setDisplay(.none);
            return;
        }
        const selected = @min(index, self.record.targets.len - 1);
        if (selected != self.record.selected) self.positions.resetTarget();
        self.record.selected = selected;
        const target = self.record.targets[self.record.selected];
        const result = target.result;
        const terminal = std.mem.eql(u8, self.record.name, "run_command") or std.mem.eql(u8, self.record.name, "read_terminal");
        const label = if (result.cwd != null or terminal) try std.fmt.allocPrint(self.cx.allocator, "目录 {s}", .{result.cwd orelse "未知"}) else try self.cx.allocator.dupe(u8, "");
        defer self.cx.allocator.free(label);
        try self.identity.setTextContent(self.cx.allocator, label);
        self.identity.setDisplay(if (label.len == 0) .none else .flex);
        const exit = if (result.exit) |code| try std.fmt.allocPrint(self.cx.allocator, "退出码 {d}", .{code}) else try self.cx.allocator.dupe(u8, if (terminal) "未获退出码" else "");
        defer self.cx.allocator.free(exit);
        const signal = if (result.signal) |value| try std.fmt.allocPrint(self.cx.allocator, "{s}信号 {d}", .{ if (exit.len != 0) " · " else "", value }) else try self.cx.allocator.dupe(u8, "");
        defer self.cx.allocator.free(signal);
        const receipt = if (target.operation_id) |operation_id| try std.fmt.allocPrint(self.cx.allocator, "操作 #{d} · {s}", .{ operation_id, if (result.local_released) "本地资源已释放" else "清理待核实" }) else try self.cx.allocator.dupe(u8, "");
        defer self.cx.allocator.free(receipt);
        const metadata = try std.fmt.allocPrint(self.cx.allocator, "{s}{s}{s}{s}{s}", .{ exit, signal, if (result.truncated) (if (exit.len != 0 or signal.len != 0) " · 输出已截断" else "输出已截断") else "", if (receipt.len != 0 and (exit.len != 0 or signal.len != 0 or result.truncated)) " · " else "", receipt });
        defer self.cx.allocator.free(metadata);
        try self.metadata.setTextContent(self.cx.allocator, metadata);
        self.metadata.setDisplay(if (metadata.len == 0) .none else .flex);
        const state_label = if (!result.local_released and result.remote_effect_unknown) "清理待核实 · 远端执行结果待核实" else if (!result.local_released) "清理待核实" else if (target.feedback) |info| info.label else if (result.remote_effect_unknown) "远端执行结果待核实" else errorStatusLabel(result.status, result.error_code, self.record.name);
        try self.showDiagnostic(target.feedback);
        const feedback = if (if (target.feedback == null) failureReason(result.error_code) else null) |reason| try std.fmt.allocPrint(self.cx.allocator, "{s} · {s}", .{ state_label, reason }) else try self.cx.allocator.dupe(u8, state_label);
        defer self.cx.allocator.free(feedback);
        try self.feedback.setTextContent(self.cx.allocator, feedback);
        try self.showOutput(result.stdout, result.stderr);
    }
    fn showOutput(self: *State, output: []const u8, failure: []const u8) !void {
        const stdout = try displayBytes(self.cx.allocator, output);
        defer self.cx.allocator.free(stdout);
        const stderr = try displayBytes(self.cx.allocator, failure);
        defer self.cx.allocator.free(stderr);
        self.stdout_code.set(stdout);
        self.stderr_code.set(stderr);
        self.stdout_label.?.setDisplay(if (stdout.len == 0) .none else .flex);
        self.stdout_viewport.?.setDisplay(if (stdout.len == 0) .none else .flex);
        self.stderr_label.?.setDisplay(if (stderr.len == 0) .none else .flex);
        self.stderr_viewport.?.setDisplay(if (stderr.len == 0) .none else .flex);
        self.copy_stdout_button.?.setDisplay(if (stdout.len == 0) .none else .flex);
        self.copy_stderr_button.?.setDisplay(if (stderr.len == 0) .none else .flex);
        self.cx.requestRedraw();
    }
    /// One output well: a native W.CodeBlock in the card body, its offsets bound to the record's
    /// position for `slot` (restored on mount, saved as they settle).
    fn mountWell(self: *State, parent: *ui.Node, code: *ui.Signal([]const u8), slot: Positions.Slot, body_id: []const u8, text_id: []const u8) !*ui.Node {
        const block = try ui.widgets.CodeBlock(.{
            .code = code,
            .options = S.wellOptions(self.space),
            .test_ids = .{ .wrap = null, .copy = null, .body = body_id, .text = text_id },
            .scroll_x = self.positions.scrollX(slot),
            .scroll_y = self.positions.scrollY(slot),
            .on_scroll_x_change = self.positions.onX(self.cx, slot),
            .on_scroll_y_change = self.positions.onY(self.cx, slot),
        }).mount(self.scope, self.cx);
        block.setStyleInline(self.cx.allocator, .{ .width = .fill(), .min_width = 0, .flex_shrink = 0 });
        try parent.appendChild(self.cx.allocator, block);
        return block;
    }
    fn applyExpanded(self: *State) void {
        self.expanded.set(self.record.expanded);
        self.body_disclosure.setExpanded(self.record.expanded);
        self.footer_disclosure.setExpanded(self.record.expanded);
        self.root.setStyleInline(self.cx.allocator, .{ .height = .{ .fit = .{} } });
    }
    fn toggle(self: *State) void {
        if (self.on_toggle) |handler| handler.invoke();
        self.record.expanded = !self.record.expanded;
        self.applyExpanded();
        self.cx.requestRedraw();
    }
    fn copy(self: *State, button: *@import("../../../../shared/ui/components/copy_button/copy_button.zig").Button, bytes: []const u8) void {
        const display = displayBytes(self.cx.allocator, bytes) catch {
            button.report(false);
            return;
        };
        defer self.cx.allocator.free(display);
        // The outcome remains visible after a copy, especially unknown effects.
        button.copy(display);
    }
    fn copyCommand(self: *State) void {
        self.copy(self.copy_command_feedback, self.record.command);
    }
    fn copyStdout(self: *State) void {
        if (self.record.host) |fact| {
            self.copy(self.copy_stdout_feedback, fact.content);
            return;
        }
        if (self.record.targets.len > 0) self.copy(self.copy_stdout_feedback, self.record.targets[self.record.selected].result.stdout);
    }
    fn copyStderr(self: *State) void {
        if (self.record.targets.len > 0) self.copy(self.copy_stderr_feedback, self.record.targets[self.record.selected].result.stderr);
    }
};
const Row = struct {
    view: *State,
    index: usize,
    test_id: [96]u8 = @splat(0),
    label: ?[]u8 = null,
    fn cleanup(self: *Row) void {
        if (self.label) |label| self.view.cx.allocator.free(label);
    }
    fn select(self: *Row) void {
        self.view.select(self.index) catch {};
    }
};
fn ownerIsGroup(owner: scope_mod.Owner) bool {
    return owner == .group;
}
fn ownerId(owner: scope_mod.Owner) u64 {
    return switch (owner) {
        .session => |id| id,
        .group => |id| id,
    };
}
fn remoteUnknown(result: @import("../../../../ai/tool_loop.zig").TargetResult) bool {
    return result.remote_effect_unknown;
}
fn targetStatus(target: facts.Target, buffer: []u8) []const u8 {
    const result = target.result;
    const label = if (target.feedback) |info| info.label else statusLabel(result.status);
    return std.fmt.bufPrint(buffer, "{s}{s}", .{ label, if (remoteUnknown(result)) " · 远端待核实" else "" }) catch label;
}
fn displayBytes(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    return @import("../model/formatted_output.zig").format(allocator, bytes);
}

fn errorStatusLabel(status: @import("../../../../ai/tool_loop.zig").Status, code: ?[]const u8, name: []const u8) []const u8 {
    if ((status == .rejected or status == .failed) and kvm_feedback.isTool(name)) {
        if (code) |value| if (kvm_feedback.failure(value)) |info| return info.label;
    }
    return statusLabel(status);
}

fn statusLabel(status: @import("../../../../ai/tool_loop.zig").Status) []const u8 {
    return switch (status) {
        .succeeded => "已完成",
        .failed => "执行失败",
        .rejected => "已拒绝",
        .cancelled => "已取消",
        .timed_out => "执行超时",
        .unknown => "结果待核实",
        .skipped => "已跳过",
    };
}

fn failureReason(code: ?[]const u8) ?[]const u8 {
    const value = code orelse return null;
    if (std.mem.eql(u8, value, "GroupMembershipChanged")) return "组成员已变化，原批准失效";
    if (std.mem.eql(u8, value, "GroupRemoved")) return "原终端组已关闭";
    if (std.mem.eql(u8, value, "StaleBinding") or std.mem.eql(u8, value, "StaleSession")) return "原会话已失效";
    if (std.mem.eql(u8, value, "ServiceUnavailable") or std.mem.eql(u8, value, "ToolHostUnavailable")) return "原会话服务不可用";
    if (std.mem.eql(u8, value, "TargetOutsideAssistant")) return "目标不在原助手范围内";
    if (std.mem.eql(u8, value, "ToolApprovalRejected")) return "本次执行未获批准";
    if (std.mem.eql(u8, value, "UnknownDirectory")) return "原会话工作目录未知";
    return null;
}

const ImagePreview = struct {
    app: ?*@import("zenit_app").App,
    reference: @import("../../../../ai/image_attachments.zig").ContentRef,
    texture: ?u32 = null,
    fn cleanup(self: *ImagePreview) void {
        if (self.texture) |texture| if (self.app) |app| app.renderer.image_renderer.unloadTexture(texture);
        self.reference.release();
    }
};

/// Re-applies a token style to a node the step views style through a widget's own box (a
/// ScrollArea container): the token values follow the theme like a styled box.
pub fn followTheme(cx: *ui.Cx, scope: *ui.Scope, node: *ui.Node, comptime style: fn (*const ui.ThemeTokens) ui.BoxStyle) !void {
    try scope.createEffect(.{ .node = node, .cx = cx, .publication = try cx.themeSignal() }, struct {
        fn run(ctx: anytype) void {
            _ = ctx.publication.get();
            ctx.node.setStyleInline(ctx.cx.allocator, style(ctx.cx.tokens));
        }
    }.run);
}
