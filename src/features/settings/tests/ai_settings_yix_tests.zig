//! AI 辅助面板正文（F-set-ai，`view/panes/ai*.yix` + `model/ai_pane.zig`）的组件测试：两级导航与保存作用域、
//! 行为与权限的设置行、宿主回来的模型清单 / 测试结果、技能与 MCP、原生对话框。夹具挂真实 `.yix` 设置窗口 +
//! 真 `ViewModel` + Ports 替身（宿主状态由用例直接给出，`Effect.ai` 只记录，不发任何网络请求）。
const std = @import("std");
const ui = @import("ui");
const kit = @import("../../../shared/testing/ui_kit.zig");
const Config = @import("../../../config/config.zig");
const ext = @import("../../../config/ai_extensions.zig");
const Controller = @import("../model/settings_controller.zig").Controller;
const m = @import("../model/view_model.zig");
const A = m.ai;
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
    jobs: std.ArrayList(A.Job) = .empty,
    effects: std.ArrayList(std.meta.Tag(m.Effect)) = .empty,
    host: A.HostAi = .{},
    models: [2]Config.AiModel = undefined,
    slots: [2]Config.AiProvider = undefined,

    fn init(self: *Fixture, value_in: ?Config.Config) !void {
        const a = std.testing.allocator;
        self.* = .{ .env = try kit.headless(a, .{ .width = shell.window.width, .height = shell.window.height, .root_style = .{ .width = .fill(), .height = .fill(), .direction = .column } }), .controller = undefined, .vm = undefined, .frame = undefined };
        self.models = .{ .{ .id = "configured-model", .context_window = 200000, .default = true, .reasoning = true, .vision = true, .efforts = .{ false, false, true, false, false, false, false } }, .{ .id = "second-model", .context_window = 8192, .default = true } };
        self.slots = .{
            .{ .name = "团队模型网关", .kind = .openai_compat, .endpoint = "https://example.test/v1", .api_key = "k", .enabled = true, .models = self.models[0..1], .model_count = 1 },
            .{ .name = "本地开发服务", .kind = .ollama, .endpoint = "http://127.0.0.1:11434/api/chat", .enabled = false, .models = self.models[1..2], .model_count = 1 },
        };
        var value: Config.Config = value_in orelse .{};
        if (value_in == null) {
            value.ai.providers = &self.slots;
            value.ai.provider_count = 2;
            value.ai.default_provider = "团队模型网关";
        }
        self.controller = try Controller.init(a, value);
        self.controller.drill_down = true;
        self.controller.navigate(.{ .page = 4, .sub = 0 });
        self.controller.history.reset(self.controller.location());
        self.vm = m.ViewModel.init(&self.controller, .{ .context = self, .run = run, .allow = allow, .status = status });
        self.frame = .{ .vm = &self.vm };
        try self.vm.attach(self.env.scope);
        self.root = try ui.view.render(self.env.scope, self.env.cx, settings_window.SettingsWindow(.{ .vm = &self.vm, .frame = &self.frame }));
        try self.env.mount(self.root);
        self.env.cx.content_root = self.root;
        self.settle();
    }
    fn deinit(self: *Fixture) void {
        self.vm.ai = .{};
        self.settle();
        self.env.deinit();
        self.jobs.deinit(std.testing.allocator);
        self.effects.deinit(std.testing.allocator);
        self.controller.deinit();
    }
    fn run(raw: *anyopaque, effect: m.Effect) void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        self.effects.append(std.testing.allocator, effect) catch {};
        switch (effect) {
            .navigated, .rebuild => self.remount = true,
            .ai => |job| self.jobs.append(std.testing.allocator, job) catch {},
            else => {},
        }
    }
    fn allow(_: *anyopaque, _: m.Gate) bool {
        return true;
    }
    fn status(raw: *anyopaque) m.HostStatus {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        return .{ .ai = self.host };
    }
    fn changed(_: *anyopaque) void {}
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
    fn send(self: *Fixture, command: A.Command) void {
        self.vm.dispatch(m.Intent.aiDo(command));
        self.settle();
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
    fn click(self: *Fixture, id: []const u8) !void {
        self.env.cx.layout();
        const rect = (try self.expect(id)).globalRect();
        self.env.cx.handleMouseMove(rect.x + rect.w / 2, rect.y + rect.h / 2);
        self.env.cx.handleMouseDown(rect.x + rect.w / 2, rect.y + rect.h / 2, .{});
        self.env.cx.handleMouseUp(rect.x + rect.w / 2, rect.y + rect.h / 2);
        self.env.cx.handleMouseMove(0, 0);
        self.settle();
    }
    fn text(self: *Fixture, id: []const u8, buffer: []u8) ![]const u8 {
        var used: usize = 0;
        collect(try self.expect(id), buffer, &used);
        return buffer[0..used];
    }
    fn lastJob(self: *Fixture) ?A.Job {
        return if (self.jobs.items.len != 0) self.jobs.items[self.jobs.items.len - 1] else null;
    }
};
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

test "ai settings pane ids keep the frozen provider, model and extension ids" {
    try std.testing.expectEqualStrings("settings.ai.provider.3.header", A.providerId(3, "header"));
    try std.testing.expectEqualStrings("settings.ai.provider.1.model.2.delete_model", A.modelId(1, 2, "delete_model"));
    try std.testing.expectEqualStrings("settings.skill.0.toggle", A.skillId(0, "toggle"));
    try std.testing.expectEqualStrings("settings.mcp.field.oauth_scope", A.mcpFieldId(.oauth_scope));
    try std.testing.expectEqualStrings("", A.providerId(A.id_providers, "header"));
    const parsed = A.parseFieldId("settings.ai.provider.12.endpoint").?;
    try std.testing.expectEqual(@as(usize, 12), parsed.provider);
    try std.testing.expectEqual(A.Field.endpoint, parsed.field);
    try std.testing.expect(A.parseFieldId("settings.ai.provider.1.kind") == null);
}

test "ai settings providers are two levels: the list opens a detail page, back returns, and the scope stays the providers subpage" {
    var f: Fixture = undefined;
    try f.init(null);
    defer f.deinit();
    var buffer: [256]u8 = undefined;
    // 列表：名称、协议与模型数、默认、未启用。
    try std.testing.expect(contains(try f.text("settings.ai.provider.0.header", &buffer), "团队模型网关"));
    try std.testing.expect(contains(try f.text("settings.ai.provider.0.header", &buffer), "OpenAI 兼容 · 1 个模型"));
    try std.testing.expect(f.displayed("settings.ai.provider.0.default"));
    try std.testing.expect(!f.displayed("settings.ai.provider.1.default"));
    try std.testing.expect(contains(try f.text("settings.ai.provider.1.header", &buffer), "已停用"));
    try std.testing.expect(f.displayed("settings.reset"));
    // 进入详情页：位置的第三级、页头标题是提供方名称；详情页没有“恢复默认…”（会清掉全部提供方）。
    try f.click("settings.ai.provider.1.header");
    try std.testing.expectEqual(m.Location{ .page = 4, .sub = 0, .ai_provider = 1 }, f.vm.location());
    try std.testing.expectEqualStrings("本地开发服务", f.vm.title());
    try std.testing.expect(f.displayed("settings.ai.provider.1.detail"));
    try std.testing.expect(!f.displayed("settings.ai.provider.0.header"));
    try std.testing.expect(!f.displayed("settings.reset"));
    try std.testing.expect(f.vm.backEnabled());
    // 带着提供方草稿回到列表、再进另一个提供方：同一作用域，不弹确认。
    f.send(.{ .edit_text = .{ .provider = 1, .field = .name, .text = "本地服务" } });
    try std.testing.expect(f.vm.isDirty());
    f.vm.dispatch(.back);
    f.settle();
    try std.testing.expectEqual(m.Location{ .page = 4, .sub = 0 }, f.vm.location());
    try std.testing.expectEqual(m.Prompt.none, f.vm.promptKind());
    try std.testing.expect(f.displayed("settings.ai.provider.0.header"));
    try std.testing.expect(contains(try f.text("settings.ai.provider.1.header", &buffer), "本地服务"));
    // 离开作用域（行为与权限）才确认。
    f.vm.dispatch(m.Intent.openAt(.{ .page = 4, .sub = 1 }));
    f.settle();
    try std.testing.expectEqual(m.Prompt.leave, f.vm.promptKind());
    f.vm.dispatch(m.Intent.decideWith(.cancel));
    f.settle();
}

test "ai settings detail page: deleting a provider confirms in a native Modal and returns to the list; the default is protected" {
    var f: Fixture = undefined;
    try f.init(null);
    defer f.deinit();
    try f.click("settings.ai.provider.0.header");
    // 已启用的默认提供方不能删（按钮禁用）。
    try std.testing.expect((try f.expect("settings.ai.provider.0.delete_provider")).behavior.interaction.a11y.?.disabled);
    f.vm.dispatch(.back);
    f.settle();
    try f.click("settings.ai.provider.1.header");
    try f.click("settings.ai.provider.1.delete_provider");
    const body = try f.expect("settings.ai.delete.dialog");
    var cursor: ?*ui.Node = body;
    const panel = while (cursor) |node| : (cursor = node.parent) {
        if (node.behavior.interaction.a11y) |a| if (a.role == .dialog) break node;
    } else return error.TestNoModalPanel;
    // 原生 Modal 默认面板（不透明、没有覆盖），焦点在“取消”。
    try std.testing.expect(panel.getBackground().a == 255);
    const focused = f.env.cx.focus_manager.getFocused() orelse return error.TestNothingFocused;
    try std.testing.expect(focused.isDescendantOf(try f.expect("settings.ai.delete.cancel")) or focused == try f.expect("settings.ai.delete.cancel"));
    var buffer: [256]u8 = undefined;
    try std.testing.expect(contains(try f.text("settings.ai.delete.dialog", &buffer), "将删除“本地开发服务”及其模型配置。"));
    try f.click("settings.ai.delete.confirm");
    try std.testing.expect(f.find("settings.ai.delete.dialog") == null);
    try std.testing.expectEqual(@as(usize, 1), f.controller.model.value.ai.provider_count);
    try std.testing.expectEqual(m.Location{ .page = 4, .sub = 0 }, f.vm.location());
    try std.testing.expect(f.displayed("settings.ai.provider.0.header"));
}

test "ai settings model catalog comes from the host: fetch is an Effect, picking a candidate fills the editor, test results follow the form" {
    var f: Fixture = undefined;
    try f.init(null);
    defer f.deinit();
    try f.click("settings.ai.provider.0.header");
    try f.click("settings.ai.provider.0.fetch_models");
    try std.testing.expectEqual(@as(usize, 0), f.lastJob().?.fetch_models);
    // 宿主回来的清单（连接签名与草稿一致才算这个提供方的）。
    const candidates = [_]Config.AiModel{ .{ .id = "gpt-4.1", .context_window = 1_000_000, .reasoning = false, .vision = true }, .{ .id = "o3", .context_window = 200_000, .reasoning = true, .efforts = .{ true, true, true, false, false, false, false } } };
    const known = [_][2]bool{ .{ true, true }, .{ true, false } };
    f.host = .{ .catalog_provider = 0, .catalog_signature = A.connectionSignature(f.controller.model.value.ai.providers[0]), .catalog_message = "模型清单已获取，添加模型时可下拉选择。", .catalog_models = &candidates, .catalog_known = &known };
    f.vm.sync();
    f.settle();
    var buffer: [512]u8 = undefined;
    try std.testing.expect(contains(try f.text("settings.ai.provider.0.catalog_status", &buffer), "模型清单已获取"));
    try f.click("settings.ai.provider.0.add_model");
    try std.testing.expect(f.displayed("settings.ai.model.dialog"));
    f.send(.{ .editor_pick = "o3" });
    try std.testing.expectEqualStrings("o3", A.editorId(&f.vm));
    try std.testing.expectEqualStrings("200000", A.editorContext(&f.vm));
    try std.testing.expectEqualStrings("yes", A.capabilityValue(&f.vm, .reasoning).?);
    try std.testing.expectEqualStrings("unknown", A.capabilityValue(&f.vm, .vision).?);
    try std.testing.expectEqual(A.Source.api, A.contextSource(&f.vm));
    try std.testing.expect(f.displayed("settings.ai.model.efforts"));
    // 测试模型：宿主执行；结果只对发起时的同一表单有效。
    f.send(.editor_test);
    const request = f.lastJob().?.test_model;
    try std.testing.expectEqualStrings("o3", request.model.id);
    f.host.test_signature = request.signature;
    f.host.test_message = "模型请求已完成。";
    f.vm.sync();
    f.settle();
    try std.testing.expectEqualStrings("模型请求已完成。", try f.text("settings.ai.model.test_status", &buffer));
    f.send(.{ .editor_context = "128000" });
    try std.testing.expectEqualStrings("未测试", try f.text("settings.ai.model.test_status", &buffer));
    // 识图能力未返回：保存前要手动选。
    try f.click("settings.ai.model.save");
    try std.testing.expect(contains(try f.text("settings.ai.model.error", &buffer), "识图能力"));
    f.send(.{ .editor_capability = .{ .which = .vision, .value = "no" } });
    try f.click("settings.ai.model.save");
    try std.testing.expect(f.find("settings.ai.model.dialog") == null);
    try std.testing.expectEqual(@as(usize, 2), f.controller.model.value.ai.providers[0].model_count);
    try std.testing.expectEqualStrings("o3", f.controller.model.value.ai.providers[0].models[1].id);
    // 关窗收起编辑器时取消进行中的测试。
    try std.testing.expect(f.displayed("settings.ai.provider.0.model.1.card"));
}

test "ai settings behavior page: native rows edit the draft; the default provider lists only ready providers" {
    var f: Fixture = undefined;
    try f.init(null);
    defer f.deinit();
    f.vm.dispatch(m.Intent.openAt(.{ .page = 4, .sub = 1 }));
    f.settle();
    for ([_][]const u8{ "settings.ai.permissions", "settings.ai.execution", "settings.ai.conversation", "settings.ai.children", "settings.ai.context", "settings.ai.attachments", "settings.ai.behavior" }) |id| try std.testing.expect(f.displayed(id));
    try std.testing.expect(!f.displayed("settings.ai.providers"));
    for ([_][]const u8{ "settings.field.permission_mode", "settings.field.execution_mode", "settings.field.session_retention", "settings.field.follow_up_mode", "settings.field.child_context_mode", "settings.field.child_reuse_policy", "settings.field.redact_ip", "settings.field.default_provider", "settings.field.step_display", "settings.field.error_hint" }) |id| try std.testing.expect(f.displayed(id));
    var buffer: [256]u8 = undefined;
    try std.testing.expect(contains(try f.text("settings.ai.attachments", &buffer), "最多 4 张 · 单张 10 MiB"));
    try std.testing.expect(contains(try f.text("settings.ai.attachments", &buffer), "UTF-8 · 64 KiB"));
    try f.click("settings.field.redact_ip");
    try std.testing.expect(f.controller.model.value.ai.redact_ip);
    f.vm.dispatch(m.Intent.editValue(.{ .section = "ai", .key = "permission_mode" }, .{ .text = "auto" }));
    f.settle();
    try std.testing.expectEqual(Config.PermissionMode.auto, f.controller.model.value.ai.permission_mode);
    const choices = A.providerChoices(&f.vm);
    try std.testing.expectEqual(@as(usize, 2), choices.len);
    try std.testing.expect(!choices[0].disabled);
    try std.testing.expect(choices[1].disabled);
    // 恢复默认只改本页。
    try std.testing.expect(f.displayed("settings.reset"));
}

fn hex(comptime n: usize, comptime c: u8) []const u8 {
    const bytes: [n]u8 = @splat(c);
    const final = bytes;
    return &final;
}

test "ai settings skills and MCP: switches and menus edit the extensions draft, host jobs are Effects, the MCP form applies a server" {
    var skills = [_]ext.Skill{.{ .id = hex(32, 'a'), .revision = hex(64, 'b'), .name = "release-notes", .description = "写发布说明", .enabled = true }};
    var value: Config.Config = .{};
    value.ai.extensions = .{ .skills = &skills };
    var f: Fixture = undefined;
    try f.init(value);
    defer f.deinit();
    f.vm.dispatch(m.Intent.openAt(.{ .page = 4, .sub = 2 }));
    f.settle();
    var buffer: [256]u8 = undefined;
    try std.testing.expectEqualStrings("1 个技能 · 1 个启用", try f.text("settings.skills.summary", &buffer));
    try f.click("settings.skill.0.toggle");
    try std.testing.expect(!f.controller.model.value.ai.extensions.skills[0].enabled);
    try std.testing.expectEqualStrings("1 个技能 · 0 个启用", try f.text("settings.skills.summary", &buffer));
    try f.click("settings.skills.add");
    try std.testing.expect(f.lastJob().? == .pick_skill);
    try f.click("settings.skill.0.view");
    try std.testing.expectEqual(@as(usize, 0), f.lastJob().?.read_skill);
    // 宿主读回 SKILL.md：展开详情。
    f.host = .{ .detail = "# release-notes", .detail_open = true, .detail_target = .{ .skill = .{ .id = skills[0].id, .revision = skills[0].revision } } };
    f.vm.sync();
    f.settle();
    try std.testing.expect(f.displayed("settings.extensions.detail"));
    try std.testing.expectEqualStrings("收起", try f.text("settings.skill.0.view", &buffer));
    // 宿主任务失败：提示显示出来。
    f.host = .{ .status = "未找到 SKILL.md，请选择技能文件或包含技能的目录。", .status_error = true };
    f.vm.sync();
    f.settle();
    try std.testing.expect(contains(try f.text("settings.extensions.status", &buffer), "未找到 SKILL.md"));
    f.host = .{};
    // MCP：添加表单 → 应用到草稿。
    try f.click("settings.mcp.add");
    try std.testing.expect(f.displayed("settings.mcp.field.program"));
    try std.testing.expect(!f.displayed("settings.mcp.add"));
    f.send(.{ .mcp_text = .{ .field = .name, .text = "local-tools" } });
    f.send(.{ .mcp_text = .{ .field = .program, .text = "/usr/bin/true" } });
    // 表单很长，按钮在视口下方：直接发同一个动作（按钮的 onClick）。
    f.send(.mcp_apply);
    try std.testing.expectEqual(@as(usize, 1), f.controller.model.value.ai.extensions.servers.len);
    try std.testing.expectEqualStrings("local-tools", f.controller.model.value.ai.extensions.servers[0].name);
    try std.testing.expect(!f.controller.model.value.ai.extensions.servers[0].enabled);
    try std.testing.expect(!f.displayed("settings.mcp.field.program"));
    try std.testing.expect(contains(try f.text("settings.mcp.0.metadata", &buffer), "本地 · true · 未测试"));
    try std.testing.expect((try f.expect("settings.mcp.0.view")).behavior.interaction.a11y.?.disabled);
    try f.click("settings.mcp.0.test");
    try std.testing.expectEqual(@as(usize, 0), f.lastJob().?.test_server);
    f.send(.{ .server_menu = .{ .index = 0, .id = "remove" } });
    try std.testing.expectEqual(@as(usize, 0), f.controller.model.value.ai.extensions.servers.len);
    // 无效超时：行内提示，草稿不变。
    try f.click("settings.mcp.add");
    f.send(.{ .mcp_text = .{ .field = .timeout, .text = "abc" } });
    // 表单很长，按钮在视口下方：直接发同一个动作（按钮的 onClick）。
    f.send(.mcp_apply);
    try std.testing.expect(contains(try f.text("settings.extensions.status", &buffer), "超时需为 100–120000 毫秒"));
    f.send(.mcp_cancel);
    try std.testing.expect(!f.displayed("settings.mcp.field.name"));
}

/// 子树里第一个带 `id` 的节点（同名 id 只在一处挂载时用）。
fn within(node: *ui.Node, id: []const u8) ?*ui.Node {
    return kit.findByTestId(node, id);
}

test "ai settings 3f parity: required API Key mark, a new provider focuses its name, an exact typed model ID takes the catalog metadata" {
    var f: Fixture = undefined;
    try f.init(null);
    defer f.deinit();
    // 必填的 API Key 带“*”（同名称、API 地址；旧视图同）；本机 Ollama 不需要密钥，写“可选”。
    try std.testing.expectEqualStrings("API Key *", A.apiKeyLabel(&f.vm, 0));
    try std.testing.expectEqualStrings("API Key（可选）", A.apiKeyLabel(&f.vm, 1));
    // 新增提供方：进入它的详情页，焦点落在“服务提供方名称”（旧视图新增后聚焦名称）。
    f.send(.add_provider);
    try std.testing.expectEqual(m.Location{ .page = 4, .sub = 0, .ai_provider = 2 }, f.vm.location());
    const focused = f.env.cx.focus_manager.getFocused() orelse return error.TestNothingFocused;
    const name = try f.expect("settings.ai.provider.2.name");
    try std.testing.expect(focused == name or focused.isDescendantOf(name));
    f.send(.{ .cancel_provider = 2 });
    // 手输的模型 ID 恰好在清单里：回车按选中处理，带出上下文与能力（清单下拉只列前 200 项）。
    try f.click("settings.ai.provider.0.header");
    const candidates = [_]Config.AiModel{.{ .id = "gpt-4.1", .context_window = 1_000_000, .reasoning = false, .vision = true }};
    const known = [_][2]bool{.{ true, true }};
    f.host = .{ .catalog_provider = 0, .catalog_signature = A.connectionSignature(f.controller.model.value.ai.providers[0]), .catalog_models = &candidates, .catalog_known = &known };
    f.vm.sync();
    f.settle();
    try f.click("settings.ai.provider.0.add_model");
    f.send(.{ .editor_id = "gpt-4.1" });
    try std.testing.expectEqualStrings("", A.editorContext(&f.vm));
    f.send(.{ .editor_id_submit = "gpt-4.1" });
    try std.testing.expectEqualStrings("gpt-4.1", A.editorId(&f.vm));
    try std.testing.expectEqualStrings("1000000", A.editorContext(&f.vm));
    try std.testing.expectEqualStrings("yes", A.capabilityValue(&f.vm, .vision).?);
    // 选中后再按回车不覆盖手改的上下文。
    f.send(.{ .editor_context = "500000" });
    f.send(.{ .editor_id_submit = "gpt-4.1" });
    try std.testing.expectEqualStrings("500000", A.editorContext(&f.vm));
    // 不在清单里的 ID 只是手输值。
    f.send(.{ .editor_id = "custom-model" });
    f.send(.{ .editor_id_submit = "custom-model" });
    try std.testing.expectEqualStrings("custom-model", A.editorId(&f.vm));
    try std.testing.expectEqualStrings("", A.editorContext(&f.vm));
    f.send(.editor_cancel);
}

test "ai settings 3f parity: extension switches and the tool view name their item; status stays in the card it belongs to" {
    var skills = [_]ext.Skill{.{ .id = hex(32, 'a'), .revision = hex(64, 'b'), .name = "release-notes", .description = "写发布说明", .enabled = true }};
    var servers = [_]ext.Server{.{ .id = hex(32, 'c'), .name = "local-tools", .program = "/usr/bin/true" }};
    var value: Config.Config = .{};
    value.ai.extensions = .{ .skills = &skills, .servers = &servers };
    var f: Fixture = undefined;
    try f.init(value);
    defer f.deinit();
    f.vm.dispatch(m.Intent.openAt(.{ .page = 4, .sub = 2 }));
    f.settle();
    try std.testing.expectEqualStrings("停用 release-notes", (try f.expect("settings.skill.0.toggle")).behavior.interaction.a11y.?.label.?);
    try std.testing.expectEqualStrings("启用 local-tools", (try f.expect("settings.mcp.0.toggle")).behavior.interaction.a11y.?.label.?);
    try std.testing.expectEqualStrings("查看工具详情", (try f.expect("settings.mcp.0.view")).behavior.interaction.a11y.?.label.?);
    f.host = .{ .status = "未找到 SKILL.md，请选择技能文件或包含技能的目录。", .status_error = true };
    f.vm.sync();
    f.settle();
    try std.testing.expect(within(try f.expect("settings.ai.skills"), "settings.extensions.status") != null);
    try std.testing.expect(within(try f.expect("settings.ai.mcp"), "settings.extensions.status") == null);
    f.host = .{ .status = "需要网页登录", .status_error = true, .status_mcp = true };
    f.vm.sync();
    f.settle();
    try std.testing.expect(within(try f.expect("settings.ai.skills"), "settings.extensions.status") == null);
    try std.testing.expect(within(try f.expect("settings.ai.mcp"), "settings.extensions.status") != null);
    f.host = .{};
    f.vm.sync();
    f.settle();
    try std.testing.expect(f.find("settings.extensions.status") == null);
}

test "ai settings search shows matching AI panes on the results page" {
    var f: Fixture = undefined;
    try f.init(null);
    defer f.deinit();
    f.vm.dispatch(m.Intent.searchFor("redact_ip"));
    f.vm.remountContent();
    f.settle();
    try std.testing.expect(f.displayed("settings.ai.context"));
    try std.testing.expect(!f.displayed("settings.ai.providers"));
    try std.testing.expect(!f.displayed("settings.ai.permissions"));
    f.vm.dispatch(m.Intent.searchFor("Ollama"));
    f.vm.remountContent();
    f.settle();
    try std.testing.expect(f.displayed("settings.ai.providers"));
    try std.testing.expect(f.displayed("settings.ai.provider.1.header"));
}
