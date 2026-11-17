//! Isolated production composer acceptance: the real composer area (`Composer.View`, the view the AI
//! host mounts — compound Textarea, tool row with Send / Stop, decision panel, “稍后处理” capsule)
//! inside the floating panel's chrome. Fabricated requests exercise the real decision panel and the
//! real question Broker; no commands or network requests are made.
//!
//! The fixture plays the host's part and nothing more: it projects the pending request into the
//! panel's snapshot, hides the field while the panel is open, and keeps the area's margins — the
//! same calls `ai_host.zig` makes (`updateComposerInteraction`, `layoutComposerArea`).
//!
//! `--state=approval|question|pending|baseline|route|long`, `--theme=<builtin theme id>`.
const std = @import("std");
const ui = @import("ui");
const App = @import("zenit_app").App;
const Composer = @import("../view/ai_composer_view.zig");
const V = Composer.Interaction;
const Controls = Composer.Controls;
const Q = @import("../../../../ai/user_interaction.zig");
const H = @import("../../../../ai/host_tools.zig");
const theme = @import("../../../../shared/ui/theme/app_theme.zig");
const fixture_window = @import("../../../../shared/ui/window/fixture_window.zig");

const State = enum { approval, question, pending, baseline, route, long };
var initial: State = .approval;
var selected_theme: []const u8 = "dark";

/// Twenty lines: taller than the decision panel's capped body, so the request scrolls.
const long_command = "sudo systemctl restart nginx\nsudo systemctl restart nginx\nsudo systemctl restart nginx\nsudo systemctl restart nginx\nsudo systemctl restart nginx\nsudo systemctl restart nginx\nsudo systemctl restart nginx\nsudo systemctl restart nginx\nsudo systemctl restart nginx\nsudo systemctl restart nginx\nsudo systemctl restart nginx\nsudo systemctl restart nginx\nsudo systemctl restart nginx\nsudo systemctl restart nginx\nsudo systemctl restart nginx\nsudo systemctl restart nginx\nsudo systemctl restart nginx\nsudo systemctl restart nginx\nsudo systemctl restart nginx\nsudo systemctl restart nginx\n";

const Preview = struct {
    cx: *ui.Cx,
    composer: *Composer.View = undefined,
    /// The floating panel's body (conversation + composer area).
    panel: *ui.Node,
    transcript: ui.widgets.ScrollAreaResult,
    result: *ui.Node,
    broker: Q.Broker = .{},
    kind: State = .approval,
    sequence: u64 = 1,
    /// A request is waiting (decision panel or capsule); false after a decision or Stop.
    active: bool = true,
    /// `--state=pending`: postpone the first request once it is shown.
    postpone_first: bool = false,
    route: @import("../../../../ai/execution_routing.zig").Route = .batch,

    fn context() H.Context {
        return .{ .conversation_id = .{ .bytes = @splat(1) }, .task_id = .{ .bytes = @splat(2) }, .binding = .{ .session = 101 }, .binding_revision = 1, .grant_revision = 1 };
    }
    fn start(self: *Preview, kind: State) !void {
        self.broker.configure(context());
        self.kind = if (kind == .pending) .approval else kind;
        self.postpone_first = kind == .pending;
        self.sequence += 1;
        self.active = kind != .baseline;
        if (kind == .question) {
            const json = "{\"question\":\"你希望如何处理 Nginx？\",\"options\":[{\"id\":\"reload\",\"label\":\"平滑重载配置\",\"description\":\"不中断现有连接\"},{\"id\":\"restart\",\"label\":\"重启服务\",\"description\":\"可能短暂中断连接\"}]}";
            const parsed = try std.json.parseFromSlice(std.json.Value, self.cx.allocator, json, .{});
            defer parsed.deinit();
            var hash: [32]u8 = undefined;
            std.crypto.hash.sha2.Sha256.hash(json, &hash, .{});
            _ = try self.broker.begin(.{ .context = context(), .authority = .conversation_context, .operation_id = self.sequence, .turn_id = 1, .call_id = "preview-question", .tool_id = Q.contribution.definition.id, .arguments = parsed.value, .arguments_json = json, .arguments_hash = hash, .canonical_arguments_hash = try @import("../../../../ai/canonical_arguments.zig").digest(self.cx.allocator, parsed.value) }, self.cx.allocator);
        }
        try self.result.setTextContent(self.cx.allocator, "已检查 Nginx 的运行状态，当前有 23 个活动连接。需要你确认后再继续。");
        self.cx.requestRedraw();
    }
    fn act(raw: *anyopaque, ticket: V.Ticket, action: V.Action) !void {
        const self: *Preview = @ptrCast(@alignCast(raw));
        if (ticket == .question) {
            if (action != .answer) return error.InvalidInteractionAction;
            try self.broker.answer(ticket.question, action.answer.option_id, action.answer.text);
            const answer = (try self.broker.poll(ticket.question)).?;
            try self.result.setTextContent(self.cx.allocator, answer.text.text());
        } else {
            if (ticket.host.sequence != self.sequence) return error.StaleApproval;
            if (action == .route) {
                self.route = action.route;
                self.cx.requestRedraw();
                return;
            }
            try self.result.setTextContent(self.cx.allocator, if (action == .approve) "已允许此操作 · 预览不执行命令" else "已拒绝此操作 · 未执行命令");
        }
        self.active = false;
        self.cx.requestRedraw();
    }
    fn stop(raw: *anyopaque) void {
        const self: *Preview = @ptrCast(@alignCast(raw));
        self.broker.stop();
        self.active = false;
        self.result.setTextContent(self.cx.allocator, "任务已停止") catch {};
        self.cx.requestRedraw();
    }
    fn send(raw: *anyopaque) void {
        const self: *Preview = @ptrCast(@alignCast(raw));
        self.result.setTextContent(self.cx.allocator, "已发送 · 预览不请求模型") catch {};
        self.cx.requestRedraw();
    }
    fn promptChanged(_: *anyopaque, _: []const u8) void {}
    fn control(_: *anyopaque, _: Controls.Envelope) !void {}
    fn approval(self: *Preview) void {
        self.start(.approval) catch {};
    }
    fn ask(self: *Preview) void {
        self.start(.question) catch {};
    }
    fn replace(self: *Preview) void {
        self.start(self.kind) catch {};
    }

    /// The host's per-frame projection (ai_host.updateComposerInteraction / layoutComposerArea).
    fn tick(raw: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
        const self: *Preview = @ptrCast(@alignCast(raw));
        const view = self.composer.interaction;
        var options: [Q.max_options]V.Option = undefined;
        const pending = self.broker.snapshot();
        var snapshot: ?V.Snapshot = null;
        if (self.active) {
            if (pending) |*value| {
                for (value.options[0..value.option_count], 0..) |*option, index| options[index] = .{ .id = option.id.text(), .label = option.label.text(), .description = option.description.text() };
                snapshot = .{ .ticket = .{ .question = value.ticket }, .title = value.question.text(), .options = options[0..value.option_count], .allow_custom = value.allow_custom };
            } else snapshot = .{
                .ticket = .{ .host = .{ .sequence = self.sequence, .hash = @splat(7) } },
                .title = "确认重启 Nginx",
                .target = "prod-web-01",
                .detail = if (self.kind == .long) long_command else "sudo systemctl restart nginx",
                .impact = "重启会短暂中断连接。",
                .route = self.route,
                .route_selectable = self.kind == .route,
                .route_reason = if (self.kind == .route) "仅选择此命令的运行方式" else "",
            };
        }
        const was_expanded = view.expanded();
        const was_pending = view.pendingVisible();
        var changed = view.update(snapshot) catch false;
        if (self.postpone_first and view.expanded()) {
            // “稍后处理” state: the request stays pending behind its capsule.
            self.postpone_first = false;
            view.postponed = true;
            changed = (view.update(snapshot) catch false) or true;
        }
        const expanded = view.expanded();
        self.composer.controls.setInteraction(expanded);
        const field_was_shown = self.composer.field_shown.peek();
        self.composer.setFieldShown(!expanded);
        // A request is a running turn: Stop shows, Send stays for the draft.
        self.composer.setActions(self.active, true);
        var resized = field_was_shown == expanded;
        {
            // The host measures the panel body the composer area sits in (its parent there).
            const body = self.panel.globalRect();
            if (view.setMaxBody(body.h * 0.4)) resized = true;
            const margin: f32 = if (body.w <= 340) 8 else 12;
            if (self.composer.setArea(.{ .left = margin, .right = margin, .bottom = margin, .top = 6 }, 0, margin)) resized = true;
        }
        var padding = self.transcript.content.style.padding;
        padding.bottom = if (view.pendingVisible()) 32 else 0;
        self.transcript.content.setStyleInline(self.cx.allocator, .{ .padding = padding });
        return if (changed or resized or was_expanded != expanded or was_pending != view.pendingVisible()) .needs_layout else .done;
    }
    fn cleanup(self: *Preview) void {
        self.broker.stop();
        self.cx.removeAfterLayoutHook(self);
    }
};

fn mount(cx: *ui.Cx, scope: *ui.Scope) !*ui.Node {
    theme.selectTokens(@import("../../../../config/theme_registry.zig").builtinTokens(selected_theme));
    cx.setTheme(theme.widgetTheme(theme.currentName()));
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .column, .background = theme.baseColors().app.withAlpha(255) }, .{});
    // Fixture controls live in the window's title bar (after the traffic lights).
    const fixture_bar = try ui.box(cx, .{ .direction = .row, .align_items = .center, .gap = 6, .flex_shrink = 0 }, .{});
    // The real floating panel's unified chrome (native floating Card, grip, header).
    const chrome = try @import("../../../../shared/ui/float_card/float_chrome.zig").Chrome.mount(cx, scope, .{ .title = "AI 助手", .icon = ui.icons.sparkles, .accent_icon = true, .descriptor = @import("../../../../ai/float_model.zig").descriptor, .ids = .{ .root = "ai.composer.preview.panel" } });
    chrome.setSubtitle("prod-web-01");
    chrome.root.setStyleInline(cx.allocator, .{ .flex = 1 });
    try root.appendChild(cx.allocator, chrome.root);
    const panel = chrome.body;
    // A stand-in conversation above the composer: one request line and the fixture's result line.
    const scroll = try ui.widgets.ScrollArea(.{ .direction = .vertical }).mount(scope, cx);
    scroll.container.setStyleInline(cx.allocator, .{ .width = .fill(), .height = .fill(), .flex = 1, .min_height = 0, .margin = .{ .bottom = 6 } });
    scroll.container.meta.ownership.meta.test_id = "ai.conversation.viewport";
    scroll.content.setStyleInline(cx.allocator, .{ .width = .fill(), .direction = .column, .gap = 12, .padding = .{ .left = 14, .right = 14 } });
    const request = try ui.text(cx, "帮我重启一下 prod-web-01 上的 Nginx。", .{ .font_size = 13, .line_height = 1.5, .color = theme.current().fg_1, .wrap = .word });
    request.setStyleInline(cx.allocator, .{ .width = .fill(), .height = .{ .fit = .{} }, .flex_shrink = 0 });
    try scroll.content.appendChild(cx.allocator, request);
    const result = try ui.text(cx, "", .{ .font_size = 12, .line_height = 1.5, .color = theme.current().fg_1, .wrap = .word });
    result.meta.ownership.meta.test_id = "ai.composer.preview.result";
    result.setStyleInline(cx.allocator, .{ .width = .fill(), .height = .{ .fit = .{} }, .flex_shrink = 0 });
    try scroll.content.appendChild(cx.allocator, result);
    try panel.appendChild(cx.allocator, scroll.container);

    const state = try scope.createState(Preview, .{ .cx = cx, .panel = panel, .transcript = scroll, .result = result });
    try scope.onCleanup(Preview, state, Preview.cleanup);
    const draft = try scope.createText("先确认当前连接数，超过 100 就暂不重启", .{ .capacity = 256 });
    state.composer = try Composer.View.mount(cx, scope, .{
        .prompt = draft,
        .callbacks = .{ .context = state, .send = Preview.send, .stop = Preview.stop, .prompt_changed = Preview.promptChanged },
        .controls = .{ .context = state, .action = Preview.control },
        .interaction = .{ .context = state, .act = Preview.act },
    });
    state.composer.sendDisabledSignal().set(false);
    try @import("../view/ai_composer_sizing.zig").bindTheme(cx, scope, state.composer.input());
    try state.composer.controls.update(.{ .owner = .{ .session = 101 }, .revision = 1 });
    // The slot the host gives the composer area (the area itself is `ai.composer`).
    const slot = try ui.box(cx, .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .flex_shrink = 0 }, .{});
    slot.meta.ownership.meta.test_id = "ai.composer.preview.composer";
    try slot.appendChild(cx.allocator, state.composer.root);
    try panel.appendChild(cx.allocator, slot);

    inline for (.{ .{ "审批", "preview.approval", Preview.approval }, .{ "问答", "preview.question", Preview.ask }, .{ "新请求", "preview.replace", Preview.replace } }) |item| {
        const button = try ui.widgets.Button(.{ .label = item[0], .on_click = cx.on(Preview, state, item[2]) }).mount(scope, cx);
        button.meta.ownership.meta.test_id = item[1];
        try fixture_bar.appendChild(cx.allocator, button);
    }
    try state.start(initial);
    try cx.addAfterLayoutHook(state, Preview.tick);
    return fixture_window.mount(cx, scope, root, .{ .background = theme.baseColors().app.withAlpha(255), .bar = fixture_bar });
}

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    while (args.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--state=")) initial = std.meta.stringToEnum(State, arg[8..]) orelse return error.InvalidState else if (std.mem.startsWith(u8, arg, "--theme=")) selected_theme = arg[8..] else return error.InvalidOption;
    }
    try @import("../../../../platform/ui_fonts.zig").register();
    const app = try App.init(std.heap.c_allocator, .{ .io = init.io, .font = .{ .fallback_families = @import("../../../../platform/ui_fonts.zig").families }, .window = .{ .width = 600, .height = 496, .title = "ZeroWork Composer Acceptance", .chrome = fixture_window.chrome, .titlebar_height = fixture_window.title_height } });
    defer app.deinit();
    try app.runWith(mount);
}
