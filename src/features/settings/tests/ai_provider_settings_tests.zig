//! AI 辅助 › 服务提供方的语义测试（F-set-ai 第一步起按 test_id 的语义断言）。
//!
//! 夹具挂真实的 `.yix` 设置窗口 + 真 `ViewModel` + 与宿主相同的 Ports 替身，用例只经 test_id、可见文字、
//! 无障碍属性、草稿（Controller）与整窗 Escape 断言：
//! - “打开某个提供方”= 点它的列表行 `settings.ai.provider.<i>.header`（进入详情页）；
//! - 宿主行为照 `SettingsHost`：导航后换纪元重挂内容页；Escape 先交 view-model（输入框组字中不接）。
const std = @import("std");
const ui = @import("ui");
const kit = @import("../../../shared/testing/ui_kit.zig");
const draft = @import("../model/settings_ai_draft.zig");
const Config = @import("../../../config/config.zig");
const runtime_config = @import("../../../config/runtime_config.zig");
const Controller = @import("../model/settings_controller.zig").Controller;
const State = @import("../model/settings_controller.zig").State;
const m = @import("../model/view_model.zig");
const frame_mod = @import("../view/window_frame.zig");
const shell = @import("../view/settings_shell.zig");
const settings_window = @import("../view/_settings_window.yix.zig");

const Fixture = struct {
    env: kit.Headless,
    controller: Controller,
    vm: m.ViewModel,
    frame: frame_mod.Frame,
    root: *ui.Node = undefined,
    remount: bool = false,
    effects: std.ArrayList(std.meta.Tag(m.Effect)) = .empty,
    models: [2]Config.AiModel = undefined,
    slots: [2]Config.AiProvider = undefined,

    fn init(self: *Fixture, configured: bool, count: usize) !void {
        const a = std.testing.allocator;
        self.* = .{ .env = try kit.headless(a, .{ .width = shell.window.width, .height = shell.window.height, .root_style = .{ .width = .fill(), .height = .fill(), .direction = .column } }), .controller = undefined, .vm = undefined, .frame = undefined };
        // 与真实设置窗口一致：浮层 / 输入框的窗口级规则（OverlayHost `install`）。
        @import("../../../shared/ui/overlay/overlay_host.zig").install(self.env.cx);
        self.models = .{ .{ .id = "configured-model", .context_window = 200000, .default = true, .reasoning = true, .vision = true, .efforts = .{ false, false, true, false, false, false, false } }, .{ .id = "model-2", .context_window = 128000 } };
        self.slots = .{ Config.default_providers[0], Config.default_providers[1] };
        if (configured) {
            self.slots[0].name = "anthropic";
            self.slots[0].kind = .anthropic;
            self.slots[0].endpoint = "https://example.test/v1/messages";
            self.slots[0].api_key = "test-key";
            self.slots[0].models = self.models[0..1];
            self.slots[0].model_count = 1;
            self.slots[0].enabled = true;
        }
        var value: Config.Config = .{};
        value.ai.providers = &self.slots;
        value.ai.provider_count = count;
        self.controller = try Controller.init(a, value);
        self.controller.drill_down = true;
        self.controller.folded_sections = 0;
        self.controller.navigate(.{ .page = 4, .sub = 0 });
        self.controller.history.reset(self.controller.location());
        self.vm = m.ViewModel.init(&self.controller, .{ .context = self, .run = run, .allow = allow });
        self.frame = .{ .vm = &self.vm };
        try self.vm.attach(self.env.scope);
        self.root = try ui.view.render(self.env.scope, self.env.cx, settings_window.SettingsWindow(.{ .vm = &self.vm, .frame = &self.frame }));
        try self.env.mount(self.root);
        self.env.cx.content_root = self.root;
        self.settle();
    }
    fn deinit(self: *Fixture) void {
        self.env.deinit();
        self.effects.deinit(std.testing.allocator);
        self.controller.deinit();
    }
    fn run(raw: *anyopaque, effect: m.Effect) void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        self.effects.append(std.testing.allocator, effect) catch {};
        switch (effect) {
            .navigated => self.remount = true,
            .rebuild => self.remount = true,
            .escape => self.windowEscape(),
            else => {},
        }
    }
    fn allow(_: *anyopaque, _: m.Gate) bool {
        return true;
    }
    /// `SettingsHost.windowEscape`：view-model 的面板分层（输入法组字中不接）。
    fn windowEscape(self: *Fixture) void {
        // 真实窗口：改过的输入框已由原生 Input 回到聚焦时的值（`Cx.input_escape`，按键路由在宿主之前）。
        const focused = self.env.cx.focus_manager.getFocused();
        const composing = if (focused) |node| if (ui.widgets.input.editStateOf(node)) |state| switch (state) {
            .input => |field| field.imeIsComposing(),
            .textarea => |textarea| textarea.imeIsComposing(),
        } else false else false;
        if (!composing) _ = self.vm.consumeEscape(if (focused) |node| self.env.cx.focus_targets.targetName(self.env.cx, node) else null);
    }
    /// 一轮帧；宿主在导航 / 重建后换纪元重挂内容页（`SettingsHost.rebuildAll`）。
    fn settle(self: *Fixture) void {
        for (0..12) |_| {
            if (self.remount) {
                self.remount = false;
                self.vm.remountContent();
            }
            self.env.cx.advanceFrameClock();
            self.env.frame();
        }
    }
    fn find(self: *Fixture, id: []const u8) ?*ui.Node {
        return kit.findByTestId(self.env.cx.root.?, id);
    }
    fn expect(self: *Fixture, id: []const u8) !*ui.Node {
        return kit.expectByTestId(self.env.cx.root.?, id);
    }
    fn displayed(self: *Fixture, id: []const u8) bool {
        const node = self.find(id) orelse return false;
        return node.isDisplayedInTree() and node.globalRect().h > 0;
    }
    /// 像用户一样点一个控件：先把它滚进视口。
    fn click(self: *Fixture, id: []const u8) !void {
        self.env.cx.layout();
        const node = try self.expect(id);
        var ancestor = node.parent;
        while (ancestor) |scroll| : (ancestor = scroll.parent) {
            if (scroll.tag != .scroll) continue;
            const ctx: *ui.widgets.scroll_area.ScrollEventCtx = @ptrCast(@alignCast(scroll.behavior.events.event_context orelse continue));
            ui.widgets.scrollIntoView(ctx.state, ctx.content orelse continue, node, .nearest);
            self.env.frame();
        }
        const rect = node.globalRect();
        const x = rect.x + rect.w / 2;
        const y = rect.y + rect.h / 2;
        self.env.cx.handleMouseMove(x, y);
        self.env.cx.handleMouseDown(x, y, .{});
        self.env.cx.handleMouseUp(x, y);
        self.env.cx.handleMouseMove(0, 0);
        self.settle();
    }
    /// 打开第 i 个服务提供方（列表行）。
    fn open(self: *Fixture, index: usize) !void {
        var buffer: [64]u8 = undefined;
        try self.click(try std.fmt.bufPrint(&buffer, "settings.ai.provider.{d}.header", .{index}));
    }
    fn input(self: *Fixture, id: []const u8) !*ui.widgets.input.TextInputState {
        if (std.mem.eql(u8, id, "settings.ai.model.id") and self.find(id) == null) try self.click("settings.ai.model.catalog");
        const node = try self.expect(id);
        return @ptrCast(@alignCast(node.behavior.events.event_context.?));
    }
    fn replace(self: *Fixture, id: []const u8, value: []const u8) !void {
        const state = try self.input(id);
        inputEvent(state, .{ .key_down = .{ .key = .a, .modifiers = .{ .super = true } } });
        inputEvent(state, .{ .text_input = .{ .text = value } });
        self.settle();
        if (std.mem.eql(u8, id, "settings.ai.model.id")) {
            if (self.find("settings.ai.model.catalog.manual")) |_| try self.click("settings.ai.model.catalog.manual");
            try self.capabilities(false, false);
        }
    }
    fn capabilities(self: *Fixture, reasoning: bool, vision: bool) !void {
        try self.click("settings.ai.model.reasoning");
        try self.click(if (reasoning) "settings.ai.model.reasoning.yes" else "settings.ai.model.reasoning.no");
        try self.click("settings.ai.model.vision");
        try self.click(if (vision) "settings.ai.model.vision.yes" else "settings.ai.model.vision.no");
    }
    fn escape(self: *Fixture) void {
        self.env.cx.handleKeyDown(.escape, .{});
        self.settle();
    }
    fn text(self: *Fixture, id: []const u8, buffer: []u8) ![]const u8 {
        var used: usize = 0;
        collect(try self.expect(id), buffer, &used);
        return buffer[0..used];
    }
    fn dialogOpen(self: *Fixture) bool {
        return self.displayed("settings.ai.model.dialog");
    }
    fn deleteOpen(self: *Fixture) bool {
        return self.displayed("settings.ai.delete.dialog");
    }
    /// 直接改草稿（结构性夹具），然后像宿主一样重新投影并重挂。
    fn edited(self: *Fixture) void {
        self.vm.sync();
        self.vm.remountContent();
        self.settle();
    }
};

fn inputEvent(state: *ui.widgets.input.TextInputState, event: ui.events.Event) void {
    _ = ui.widgets.input.inputEventHandler(event, state);
}
fn collect(node: *ui.Node, buffer: []u8, used: *usize) void {
    if (node.style.display == .none) return;
    if (node.getText()) |value| {
        const n = @min(value.content.len, buffer.len - used.*);
        @memcpy(buffer[used.*..][0..n], value.content[0..n]);
        used.* += n;
    }
    for (node.children.items) |child| collect(child, buffer, used);
}
fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

test "ai provider list opens a provider's detail without editing the draft" {
    var f: Fixture = undefined;
    try f.init(true, 2);
    defer f.deinit();
    try std.testing.expect(f.displayed("settings.ai.provider.0.header"));
    try std.testing.expect(f.displayed("settings.ai.provider.1.header"));
    try f.open(1);
    try std.testing.expect(f.displayed("settings.ai.provider.1.endpoint"));
    try std.testing.expect(!f.displayed("settings.ai.provider.0.endpoint"));
    // 两级（F-set-ai）：详情页里没有列表，页头“后退”回到列表再打开别的提供方（旧 master / detail 下后退无操作）。
    f.vm.dispatch(.back);
    f.settle();
    try f.open(0);
    try std.testing.expect(f.displayed("settings.ai.provider.0.endpoint"));
    try std.testing.expect(!f.displayed("settings.ai.provider.1.endpoint"));
    try std.testing.expect(!f.controller.model.dirty);
    try std.testing.expect(f.controller.model.value.ai.providers[0].enabled);
}

test "ai provider detail shows status, connection fields, keychain hint and the model rows" {
    var f: Fixture = undefined;
    try f.init(true, 2);
    defer f.deinit();
    try f.open(0);
    var buffer: [256]u8 = undefined;
    try std.testing.expectEqualStrings("已启用", try f.text("settings.ai.provider.0.status", &buffer));
    for ([_][]const u8{ "settings.ai.provider.0.name", "settings.ai.provider.0.kind", "settings.ai.provider.0.endpoint", "settings.ai.provider.0.api_key", "settings.ai.provider.0.model.0.card" }) |id| try std.testing.expect(f.displayed(id));
    try std.testing.expect(contains(try f.text("settings.ai.provider.0.kind", &buffer), "Anthropic"));
    try std.testing.expectEqualStrings("API Key 存储于 macOS 钥匙串", (try f.expect("settings.ai.provider.0.keychain")).behavior.interaction.a11y.?.label.?);
    try std.testing.expect(contains(try f.text("settings.ai.provider.0.model.0.card", &buffer), "configured-model"));
    try std.testing.expect(!f.controller.model.dirty);
}

test "ai provider invalid endpoint keeps the raw text, marks the field invalid and Escape restores it" {
    var f: Fixture = undefined;
    try f.init(true, 1);
    defer f.deinit();
    try f.open(0);
    // 聚焦后再改：Escape 回到聚焦时的值（OverlayHost → `Cx.input_escape`）。
    f.env.cx.setFocus(try f.expect("settings.ai.provider.0.endpoint"));
    try f.replace("settings.ai.provider.0.endpoint", "gateway-without-scheme");
    try std.testing.expectEqualStrings("https://example.test/v1/messages", f.controller.model.value.ai.providers[0].endpoint);
    try std.testing.expectEqualStrings("gateway-without-scheme", f.controller.ai_fields.get(.{ .provider = 0, .field = .endpoint }).?.input);
    try std.testing.expectEqual(State.dirty_invalid, f.controller.state());
    try std.testing.expect(!f.controller.canSave());
    try std.testing.expect((try f.expect("settings.ai.provider.0.endpoint")).behavior.interaction.a11y.?.invalid);
    var buffer: [256]u8 = undefined;
    try std.testing.expect(contains(try f.text("settings.ai.provider.0.endpoint.error", &buffer), "HTTP/HTTPS"));
    // Escape：焦点在这个输入框上时撤回原文。
    f.escape();
    try std.testing.expectEqualStrings("https://example.test/v1/messages", (try f.input("settings.ai.provider.0.endpoint")).getText());
    try std.testing.expectEqual(State.clean, f.controller.state());
    try std.testing.expect(!(try f.expect("settings.ai.provider.0.endpoint")).behavior.interaction.a11y.?.invalid);
}

test "ai provider model dialog cancel preserves existing models and unrelated settings" {
    var f: Fixture = undefined;
    try f.init(true, 1);
    defer f.deinit();
    try f.open(0);
    try f.controller.editRaw("ssh", "keepalive_sec", "44");
    try f.click("settings.ai.provider.0.add_model");
    try std.testing.expect(f.dialogOpen());
    try f.replace("settings.ai.model.id", "ops-model-2");
    try f.replace("settings.ai.model.context", "128000");
    try std.testing.expectEqual(@as(usize, 1), f.controller.model.value.ai.providers[0].model_count);
    try f.click("settings.ai.model.cancel");
    try std.testing.expect(!f.dialogOpen());
    try std.testing.expectEqualStrings("configured-model", f.controller.model.value.ai.providers[0].models[0].id);
    try std.testing.expect(f.controller.model.value.ai.providers[0].models[0].default);
    try std.testing.expectEqual(@as(u16, 44), f.controller.model.value.ssh.keepalive_sec);
    try std.testing.expect(f.controller.canSave());
}

test "ai provider create local Ollama form saves vision independently and reloads without network" {
    var f: Fixture = undefined;
    try f.init(false, 0);
    defer f.deinit();
    try f.click("settings.ai.providers.empty.add");
    try std.testing.expectEqual(@as(usize, 1), f.controller.model.value.ai.provider_count);
    try f.replace("settings.ai.provider.0.name", "Production Gateway");
    try f.click("settings.ai.provider.0.kind");
    // 选择框的下拉选项按显示文字点（Ollama）。
    try clickOption(&f, "Ollama");
    try std.testing.expectEqual(Config.ProviderKind.ollama, f.controller.model.value.ai.providers[0].kind);
    try f.replace("settings.ai.provider.0.endpoint", "http://127.0.0.1:11434/api/chat");
    try f.click("settings.ai.provider.0.add_model");
    try f.replace("settings.ai.model.id", "local-model");
    try f.replace("settings.ai.model.context", "8192");
    try f.capabilities(false, true);
    try f.click("settings.ai.model.save");
    try std.testing.expect(!f.dialogOpen());
    const model = f.controller.model.value.ai.providers[0].models[0];
    try std.testing.expect(model.vision and !model.reasoning);
    try std.testing.expectEqualStrings("", f.controller.model.value.ai.providers[0].api_key);
    try std.testing.expect(f.controller.model.value.ai.providers[0].enabled);
    try f.controller.selectProvider("Production Gateway");
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var target = try runtime_config.RuntimeConfig.loadOrDefault(std.testing.io, tmp.dir, std.testing.allocator, "settings.toml");
    defer target.deinit();
    try f.controller.save(std.testing.io, tmp.dir, &target);
    var loaded = try runtime_config.RuntimeConfig.loadOrDefault(std.testing.io, tmp.dir, std.testing.allocator, "settings.toml");
    defer loaded.deinit();
    try std.testing.expect(loaded.value.ai.providers[0].models[0].vision);
    try std.testing.expect(!loaded.value.ai.providers[0].models[0].reasoning);
    try std.testing.expectEqualStrings("Production Gateway", loaded.value.ai.default_provider);
    try std.testing.expectEqual(State.clean, f.controller.state());
}
/// 点打开着的下拉面板里显示这段文字的选项。
fn clickOption(f: *Fixture, label: []const u8) !void {
    f.env.cx.layout();
    const node = findText(f.env.cx.root.?, label, f.find("settings.ai.provider.0.kind").?) orelse return error.TestOptionNotFound;
    const rect = node.globalRect();
    f.env.cx.handleMouseMove(rect.x + rect.w / 2, rect.y + rect.h / 2);
    f.env.cx.handleMouseDown(rect.x + rect.w / 2, rect.y + rect.h / 2, .{});
    f.env.cx.handleMouseUp(rect.x + rect.w / 2, rect.y + rect.h / 2);
    f.env.cx.handleMouseMove(0, 0);
    f.settle();
}
/// 显示这段文字、且不在 `except` 子树里的最后一个节点（下拉面板挂在浮层根上，排在后面）。
fn findText(node: *ui.Node, label: []const u8, except: *ui.Node) ?*ui.Node {
    var found: ?*ui.Node = null;
    if (node != except) {
        if (node.getText()) |value| if (std.mem.eql(u8, value.content, label) and node.isDisplayedInTree() and node.globalRect().h > 0) {
            found = node;
        };
        for (node.children.items) |child| if (findText(child, label, except)) |hit| {
            found = hit;
        };
    }
    return found;
}

test "ai provider model dialog rejects duplicate ids, zero windows and missing reasoning efforts without mutating the draft" {
    var f: Fixture = undefined;
    try f.init(true, 1);
    defer f.deinit();
    try f.open(0);
    var buffer: [512]u8 = undefined;
    try f.click("settings.ai.provider.0.add_model");
    try f.replace("settings.ai.model.id", "configured-model");
    try f.replace("settings.ai.model.context", "128000");
    try f.click("settings.ai.model.save");
    try std.testing.expectEqualStrings(draft.problemText(error.DuplicateModelId), try f.text("settings.ai.model.error", &buffer));
    try f.replace("settings.ai.model.id", "other");
    try f.replace("settings.ai.model.context", "0");
    try f.click("settings.ai.model.save");
    try std.testing.expectEqualStrings(draft.problemText(error.InvalidContextWindow), try f.text("settings.ai.model.error", &buffer));
    try f.click("settings.ai.model.cancel");
    try f.click("settings.ai.provider.0.model.0.edit_model");
    // 取消唯一选中的推理等级（high）。
    try f.click("settings.ai.model.effort.high");
    try f.click("settings.ai.model.save");
    try std.testing.expectEqualStrings(draft.problemText(error.LastEffortRequired), try f.text("settings.ai.model.error", &buffer));
    try std.testing.expect(f.controller.model.value.ai.providers[0].models[0].efforts[2]);
    try f.click("settings.ai.model.cancel");
    // 已启用提供方的最后一个模型不能删除。
    try std.testing.expect((try f.expect("settings.ai.provider.0.model.0.delete_model")).behavior.interaction.a11y.?.disabled);
    try std.testing.expectEqual(@as(usize, 1), f.controller.model.value.ai.providers[0].model_count);
}

test "ai provider pending save disables the controls and IME composition keeps Escape" {
    var f: Fixture = undefined;
    try f.init(true, 1);
    defer f.deinit();
    try f.open(0);
    const state = try f.input("settings.ai.provider.0.name");
    f.env.cx.setFocus(try f.expect("settings.ai.provider.0.name"));
    inputEvent(state, .{ .ime_preedit = .{ .text = "pin", .cursor_utf8_offset = 3 } });
    f.windowEscape();
    try std.testing.expect(state.imeIsComposing());
    try std.testing.expect(f.controller.ai_fields.get(.{ .provider = 0, .field = .name }) == null);
    inputEvent(state, .{ .ime_preedit = .{ .text = "", .cursor_utf8_offset = 0 } });
    f.controller.save_operation = 7;
    defer f.controller.save_operation = null;
    f.edited();
    try std.testing.expect((try f.input("settings.ai.provider.0.name")).disabled);
    const count = f.controller.model.value.ai.provider_count;
    f.vm.dispatch(.back);
    f.settle();
    if (f.find("settings.ai.add_provider")) |button| if (button.isDisplayedInTree()) {
        try f.click("settings.ai.add_provider");
    };
    try std.testing.expectEqual(count, f.controller.model.value.ai.provider_count);
}

test "ai provider endpoint policy rejects credentials fragments missing hosts and renames keep the default" {
    for ([_][]const u8{ "example.test/v1", "ftp://example.test", "http:///path", "https://u:p@example.test", "https://example.test/#fragment", "https://example.test/\x00" }) |url| try std.testing.expect(!draft.endpointValid(url));
    try std.testing.expect(draft.endpointValid("http://127.0.0.1:11434/api/chat"));
    try std.testing.expect(draft.endpointValid("https://example.test/v1/chat/completions"));
    var f: Fixture = undefined;
    try f.init(true, 1);
    defer f.deinit();
    try f.open(0);
    try f.replace("settings.ai.provider.0.name", "renamed");
    try std.testing.expectEqualStrings("renamed", f.controller.model.value.ai.default_provider);
    // 清空 API Key（输入框里删空，经同一个草稿入口）。
    f.controller.editAiRaw(.{ .provider = 0, .field = .api_key }, "") catch {};
    try std.testing.expect(!f.controller.canSave());
}

test "ai provider save problem on another provider's missing API key opens that provider and focuses the field" {
    var f: Fixture = undefined;
    try f.init(true, 1);
    defer f.deinit();
    var owned = try runtime_config.Snapshot.init(std.testing.allocator, f.controller.model.value);
    defer owned.deinit();
    const providers = try owned.arena.allocator().alloc(Config.AiProvider, 2);
    providers[0] = owned.value.ai.providers[0];
    providers[1] = .{ .name = "SCNetX", .endpoint = "https://example.test/v1", .enabled = true, .models = providers[0].models, .model_count = 1 };
    owned.value.ai.providers = providers;
    owned.value.ai.provider_count = 2;
    try f.controller.editProviders(owned.value.ai);
    const problem = f.controller.validationProblem().?;
    try std.testing.expectEqual(@as(usize, 1), problem.ai_address.?.provider);
    try std.testing.expectEqual(draft.Field.api_key, problem.ai_address.?.field);
    var buffer: [512]u8 = undefined;
    try std.testing.expectEqualStrings("SCNetX · API Key：请填写 API Key，或停用此服务提供方。", f.controller.validationMessage(&buffer));
    f.edited();
    f.vm.dispatch(.locate_problem);
    f.settle();
    const field = try f.expect("settings.ai.provider.1.api_key");
    try std.testing.expect(field.isDisplayedInTree());
    const focused = f.env.cx.focus_manager.getFocused() orelse return error.TestNothingFocused;
    try std.testing.expect(focused == field or focused.isDescendantOf(field));
    try std.testing.expect(contains(try f.text("settings.ai.provider.1.api_key.error", &buffer), "请填写 API Key，或停用此服务提供方。"));
    try f.replace("settings.ai.provider.1.api_key", "fixture-key");
    try std.testing.expect(f.controller.validationProblem() == null);
    try std.testing.expect(f.controller.canSave());
}

test "ai provider first configuration becomes saveable after the required connection fields" {
    var f: Fixture = undefined;
    try f.init(false, 0);
    defer f.deinit();
    try f.click("settings.ai.providers.empty.add");
    try std.testing.expectEqual(draft.Field.name, f.controller.validationProblem().?.ai_address.?.field);
    try f.replace("settings.ai.provider.0.name", "First provider");
    try std.testing.expectEqual(draft.Field.endpoint, f.controller.validationProblem().?.ai_address.?.field);
    try f.replace("settings.ai.provider.0.endpoint", "http://127.0.0.1:3425/v1");
    try std.testing.expect(f.controller.canSave());
    try std.testing.expect(f.controller.validationProblem() == null);
    try f.click("settings.ai.provider.0.add_model");
    try f.replace("settings.ai.model.id", "new-model");
    try f.replace("settings.ai.model.context", "128000");
    try f.click("settings.ai.model.save");
    try std.testing.expect(!f.dialogOpen());
    try std.testing.expect(f.controller.model.value.ai.providers[0].models[0].default);
    try std.testing.expect(f.controller.canSave());
}

test "ai provider add model from a focused button opens the editor and cancel restores the page" {
    var f: Fixture = undefined;
    try f.init(true, 1);
    defer f.deinit();
    try f.open(0);
    f.env.cx.setFocus(try f.expect("settings.ai.provider.0.add_model"));
    try f.click("settings.ai.provider.0.add_model");
    try std.testing.expect(f.dialogOpen());
    try std.testing.expect(f.displayed("settings.ai.model.catalog"));
    try f.replace("settings.ai.model.id", "ops-model-2");
    try f.replace("settings.ai.model.context", "128000");
    try f.click("settings.ai.model.cancel");
    try std.testing.expectEqual(@as(usize, 1), f.controller.model.value.ai.providers[0].model_count);
    try std.testing.expect(!f.dialogOpen());
    try std.testing.expect(f.find("settings.ai.model.id") == null);
    try std.testing.expect(f.displayed("settings.ai.provider.0.add_model"));
}

test "ai provider model dialog keeps an active composition and Escape then closes it" {
    var f: Fixture = undefined;
    try f.init(true, 1);
    defer f.deinit();
    try f.open(0);
    try f.click("settings.ai.provider.0.model.0.edit_model");
    const state = try f.input("settings.ai.model.id");
    f.env.cx.setFocus(try f.expect("settings.ai.model.id"));
    inputEvent(state, .{ .ime_preedit = .{ .text = "pin", .cursor_utf8_offset = 3 } });
    f.windowEscape();
    try std.testing.expect(f.dialogOpen());
    inputEvent(state, .{ .ime_preedit = .{ .text = "", .cursor_utf8_offset = 0 } });
    // 旧实现的第一下 Escape 先收起模型搜索弹层；两下之内对话框关掉。
    f.escape();
    if (f.dialogOpen()) f.escape();
    try std.testing.expect(!f.dialogOpen());
    try std.testing.expectEqualStrings("configured-model", f.controller.model.value.ai.providers[0].models[0].id);
}

fn configureInactive(f: *Fixture, index: usize, name: []const u8) !void {
    var owned = try runtime_config.Snapshot.init(std.testing.allocator, f.controller.model.value);
    defer owned.deinit();
    const p = &owned.value.ai.providers[index];
    p.name = name;
    p.kind = .ollama;
    p.endpoint = "http://127.0.0.1:9/api/chat";
    p.api_key = "";
    p.enabled = false;
    p.models = try owned.arena.allocator().alloc(Config.AiModel, 1);
    p.models[0] = .{ .id = "fixture-model", .context_window = 8192, .default = true };
    p.model_count = 1;
    try f.controller.editProviders(owned.value.ai);
    f.edited();
}

test "ai provider explicit enable protects the last default and selects an enabled replacement" {
    var f: Fixture = undefined;
    try f.init(false, 2);
    defer f.deinit();
    try configureInactive(&f, 0, "first");
    try configureInactive(&f, 1, "second");
    try f.open(0);
    try f.replace("settings.ai.provider.0.endpoint", "http://localhost:9/api/chat");
    try std.testing.expect(!f.controller.model.value.ai.providers[0].enabled);
    try f.click("settings.ai.provider.0.enabled");
    try std.testing.expect(f.controller.model.value.ai.providers[0].enabled);
    try std.testing.expectEqualStrings("first", f.controller.model.value.ai.default_provider);
    try f.click("settings.ai.provider.0.enabled");
    try std.testing.expect(f.controller.model.value.ai.providers[0].enabled);
    var buffer: [256]u8 = undefined;
    try std.testing.expectEqualStrings(draft.problemText(error.DefaultProtected), try f.text("settings.ai.provider_error", &buffer));
    f.vm.dispatch(.back);
    f.settle();
    try f.open(1);
    try f.click("settings.ai.provider.1.enabled");
    try std.testing.expect(f.controller.model.value.ai.providers[1].enabled);
    f.vm.dispatch(.back);
    f.settle();
    try f.open(0);
    try f.click("settings.ai.provider.0.enabled");
    try std.testing.expect(!f.controller.model.value.ai.providers[0].enabled);
    try std.testing.expectEqualStrings("second", f.controller.model.value.ai.default_provider);
}

test "ai provider reveal key is transient and deleting a model needs explicit confirmation" {
    var f: Fixture = undefined;
    try f.init(true, 2);
    defer f.deinit();
    try f.open(0);
    try std.testing.expectEqual(ui.widgets.InputType.password, (try f.input("settings.ai.provider.0.api_key")).input_type);
    try f.click("settings.ai.provider.0.reveal_key");
    try std.testing.expectEqual(ui.widgets.InputType.text, (try f.input("settings.ai.provider.0.api_key")).input_type);
    try f.click("settings.ai.provider.0.reveal_key");
    try std.testing.expectEqual(ui.widgets.InputType.password, (try f.input("settings.ai.provider.0.api_key")).input_type);
    try std.testing.expect(!f.controller.model.dirty);
    try configureInactive(&f, 1, "inactive");
    f.vm.dispatch(.back);
    f.settle();
    try f.open(1);
    try f.click("settings.ai.provider.1.model.0.delete_model");
    try std.testing.expect(f.deleteOpen());
    try std.testing.expectEqual(@as(usize, 1), f.controller.model.value.ai.providers[1].model_count);
    try f.click("settings.ai.delete.cancel");
    try std.testing.expect(!f.deleteOpen());
    try std.testing.expectEqual(@as(usize, 1), f.controller.model.value.ai.providers[1].model_count);
    try f.click("settings.ai.provider.1.model.0.delete_model");
    try f.click("settings.ai.delete.confirm");
    try std.testing.expect(!f.deleteOpen());
    try std.testing.expectEqual(@as(usize, 0), f.controller.model.value.ai.providers[1].model_count);
    try std.testing.expect(!f.controller.model.value.ai.providers[1].enabled);
}

test "ai provider empty registry shows the first add action and creates only a draft" {
    var f: Fixture = undefined;
    try f.init(false, 0);
    defer f.deinit();
    try std.testing.expect(f.displayed("settings.ai.providers.empty"));
    try std.testing.expect(f.find("settings.ai.provider.0.card") == null);
    try f.click("settings.ai.providers.empty.add");
    try std.testing.expectEqual(@as(usize, 1), f.controller.model.value.ai.provider_count);
    try std.testing.expect(!f.displayed("settings.ai.providers.empty"));
    try std.testing.expect(f.displayed("settings.ai.provider.0.name"));
    try std.testing.expectEqual(@as(usize, 0), f.controller.model.original.ai.provider_count);
}

test "ai provider model dialog fits a compact window" {
    var f: Fixture = undefined;
    try f.init(true, 1);
    defer f.deinit();
    f.env.cx.setViewport(860, 480);
    f.settle();
    try f.open(0);
    try f.click("settings.ai.provider.0.add_model");
    const footer = (try f.expect("settings.ai.model.footer")).globalRect();
    try std.testing.expect(footer.y >= 0 and footer.y + footer.h <= 480 + 0.1);
    try std.testing.expect(footer.x >= 0 and footer.x + footer.w <= 860 + 0.1);
    try f.click("settings.ai.model.cancel");
}

test "ai provider saves an enabled connection without models and discovers models later" {
    var f: Fixture = undefined;
    try f.init(false, 0);
    defer f.deinit();
    try f.click("settings.ai.providers.empty.add");
    try std.testing.expect(f.controller.model.value.ai.providers[0].enabled);
    try f.replace("settings.ai.provider.0.name", "Empty Gateway");
    try f.replace("settings.ai.provider.0.endpoint", "http://127.0.0.1:11434/v1");
    try std.testing.expectEqual(@as(usize, 0), f.controller.model.value.ai.providers[0].model_count);
    try std.testing.expect(f.controller.canSave());
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var target = try runtime_config.RuntimeConfig.loadOrDefault(std.testing.io, tmp.dir, std.testing.allocator, "settings.toml");
    defer target.deinit();
    try f.controller.save(std.testing.io, tmp.dir, &target);
    try std.testing.expect(target.value.ai.providers[0].enabled);
    try std.testing.expectEqual(@as(usize, 0), target.value.ai.providers[0].model_count);
}

test "ai provider switching providers keeps raw drafts" {
    var f: Fixture = undefined;
    try f.init(true, 2);
    defer f.deinit();
    try f.open(0);
    try f.replace("settings.ai.provider.0.endpoint", "invalid-raw-value");
    f.vm.dispatch(.back);
    f.settle();
    try f.open(1);
    try std.testing.expect(f.displayed("settings.ai.provider.1.endpoint"));
    try std.testing.expect(!f.displayed("settings.ai.provider.0.endpoint"));
    f.vm.dispatch(.back);
    f.settle();
    try f.open(0);
    try std.testing.expectEqualStrings("invalid-raw-value", (try f.input("settings.ai.provider.0.endpoint")).getText());
    try std.testing.expect(!f.controller.canSave());
}

fn switchThumbOffset(node: *ui.Node) f32 {
    const track = node.children.items[0];
    return track.children.items[0].globalRect().x - track.globalRect().x;
}

test "ai provider enable switch is a native zenit Switch: toggles the draft and is disabled while saving" {
    var f: Fixture = undefined;
    try f.init(false, 2);
    defer f.deinit();
    try configureInactive(&f, 0, "first");
    try configureInactive(&f, 1, "second");
    try f.open(0);
    try f.replace("settings.ai.provider.0.endpoint", "http://localhost:9/api/chat");
    const t = f.env.cx.tokens.tokens;
    const off = try f.expect("settings.ai.provider.0.enabled");
    const a11y = off.behavior.interaction.a11y.?;
    try std.testing.expectEqual(ui.A11yRole.switch_role, a11y.role);
    try std.testing.expectEqualStrings("启用服务提供方", a11y.label.?);
    try std.testing.expect(!a11y.checked.?);
    try std.testing.expectApproxEqAbs(t.size.switch_width, off.children.items[0].globalRect().w, 0.01);
    try std.testing.expectApproxEqAbs(t.size.switch_height, off.children.items[0].globalRect().h, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 2), switchThumbOffset(off), 0.01);
    try f.click("settings.ai.provider.0.enabled");
    try std.testing.expect(f.controller.model.value.ai.providers[0].enabled);
    for (0..3) |_| f.settle();
    const on = try f.expect("settings.ai.provider.0.enabled");
    try std.testing.expect(on.behavior.interaction.a11y.?.checked.?);
    try std.testing.expectApproxEqAbs(t.size.switch_width - t.size.switch_thumb - 2, switchThumbOffset(on), 0.01);
    f.controller.save_operation = 7;
    defer f.controller.save_operation = null;
    f.edited();
    try std.testing.expect((try f.expect("settings.ai.provider.0.enabled")).behavior.interaction.a11y.?.disabled);
    try f.click("settings.ai.provider.0.enabled");
    try std.testing.expect(f.controller.model.value.ai.providers[0].enabled);
}
