//! Production composition and generic content plumbing. All file IO is rooted
//! in temporary directories; no worker or real BMC endpoint is started.
const std = @import("std");
const ui = @import("ui");
const T = std.testing;
const a = T.allocator;
const composition = @import("../../application_plugins.zig");
const linked = @import("../../linked_plugins.zig");
const registry = @import("../../../host/plugin_registry.zig");
const sessions = @import("../../../host/session_host.zig");
const identity = @import("../../../host/identity.zig");
const frames = @import("../../../host/frame_texture_sink.zig");
const budgets = @import("../../../host/frame_budget.zig");
const content = @import("../../../host/content_context.zig");
const ContentHost = @import("../../../features/shell/host/plugin_content_host.zig").Host;
const bmc = @import("../plugin.zig");
const runtime_api = @import("../runtime.zig");
const controller = @import("../controller.zig");
const target: sessions.AttachmentTarget = .{ .window_id = @fromBackingInt(1), .workspace_id = @fromBackingInt(1) };

const enablement = @import("../../../host/plugin_enablement.zig");
const all_enabled: enablement.Launch = enablement.Launch.init(&composition.Bundle(true).linked, .{ .preferences = &.{} });

fn pluginFor(bundle: anytype) *bmc.Plugin {
    return @ptrCast(@alignCast(bundle.manifests()[0].session_factory.?.context));
}

test "BMC composition production includes BMC and acceptance additionally includes only its fixture" {
    var tmp = T.tmpDir(.{});
    defer tmp.cleanup();
    const path = try tmp.dir.realPathFileAlloc(T.io, ".", a);
    defer a.free(path);
    var production = try composition.Bundle(false).init(a, T.io, path, &all_enabled);
    defer production.deinit() catch unreachable;
    var normal = try linked.initRegistry(a, &.{}, production.manifests(), production.renderers());
    defer normal.deinit();
    try T.expectEqual(@as(usize, 1), normal.manifests().len);
    const manifest = normal.find("bmc_ikvm").?;
    try T.expect(normal.find("fixture_probe") == null);
    try T.expectEqual(budgets.Limits.kvm, manifest.frame_limits.?);
    try T.expectEqual(budgets.application_bytes, production.frameBudget().limit);

    var acceptance = try composition.Bundle(true).init(a, T.io, path, &all_enabled);
    defer acceptance.deinit() catch unreachable;
    var combined = try linked.initRegistry(a, &.{}, acceptance.manifests(), acceptance.renderers());
    defer combined.deinit();
    try T.expectEqual(@as(usize, 2), combined.manifests().len);
    try T.expect(combined.find("bmc_ikvm") != null);
    try T.expect(combined.find("fixture_probe") != null);
    try T.expect(combined.find("fixture_probe").?.frame_limits == null);
    // 全部生产清单与路线条目不冲突（冲突时上面的 initRegistry 已经以 RoadmapConflict 失败）；KVM 只作为已注册插件出现。
    for (@import("../../../host/plugin_roadmap.zig").entries) |entry| try T.expect(combined.find(entry.id) == null);
    try T.expectEqual(registry.Origin.bundled, manifest.origin);
    try T.expectEqualStrings("远程画面、键鼠输入、电源与启动管理", manifest.summary.?);
}

test "BMC composition Q5: a disabled bundled plugin is not initialized, registered, or exposed (tools, notifications, AI context)" {
    var tmp = T.tmpDir(.{});
    defer tmp.cleanup();
    const path = try tmp.dir.realPathFileAlloc(T.io, ".", a);
    defer a.free(path);
    const prefs = [_]@import("../../../config/config.zig").PluginPreference{
        .{ .plugin_id = "bmc_ikvm", .key = "host.enabled", .value = "false" },
        .{ .plugin_id = "ssh", .key = "host.enabled", .value = "false" },
    };
    const launch = enablement.Launch.init(&composition.Bundle(true).linked, .{ .preferences = &prefs });
    var bundle = try composition.Bundle(true).init(a, T.io, path, &launch);
    defer bundle.deinit() catch unreachable;
    // init 没有被调用：bundle 里没有 bmc 的实例，也没有打开 / 创建它的管理日志文件。
    try T.expect(bundle.resources.?.plugin == null);
    try T.expectError(error.FileNotFound, tmp.dir.access(T.io, "bmc-management-v1.json", .{}));
    var published = try linked.initRegistry(a, &.{}, bundle.manifests(), bundle.renderers());
    defer published.deinit();
    try T.expect(published.find("bmc_ikvm") == null);
    try T.expect(published.find("fixture_probe") != null);
    for (published.manifests()) |manifest| {
        for (manifest.notifications) |definition| try T.expect(!std.mem.startsWith(u8, definition.id, "bmc_ikvm."));
        for (manifest.tools) |binding| try T.expect(!std.mem.eql(u8, binding.plugin_id, "bmc_ikvm"));
    }
    // 已链接插件表仍能给出它的元数据（设置页、侧栏、向导用来区分“已禁用”和“未知插件”）。
    try T.expectEqualStrings("BMC · iKVM", launch.disabled("bmc_ikvm").?.display_name);
    try T.expect(launch.disabled("fixture_probe") == null);
    // 内置三项写了 host.enabled = false 也不生效（Q5a）：它们不在已链接插件表里，按启用处理。
    try T.expect(launch.disabled("ssh") == null);
    // 配置无法解析（Q5c）：随应用插件全部不加载。
    const closed = enablement.Launch.init(&composition.Bundle(true).linked, .unreadable);
    var none = try composition.Bundle(true).init(a, T.io, path, &closed);
    defer none.deinit() catch unreachable;
    try T.expectEqual(@as(usize, 0), none.manifests().len);
}

test "BMC composition publishes exactly injectable APIs and rejects missing or incompatible capabilities" {
    const expected = [_][]const u8{ "host", "host.session_service_access", "host.probes", "host.tls_trust", "host.secrets", "host.resource_actions", "host.frame_budget" };
    try T.expectEqual(expected.len, linked.supported_apis.len);
    for (expected, linked.supported_apis, 0..) |id, api, i| {
        try T.expectEqualStrings(id, api.id);
        try T.expectEqual(@as(u32, if (i == 0) 2 else 1), api.major);
    }
    var tmp = T.tmpDir(.{});
    defer tmp.cleanup();
    const path = try tmp.dir.realPathFileAlloc(T.io, ".", a);
    defer a.free(path);
    var bundle = try composition.Bundle(false).init(a, T.io, path, &all_enabled);
    defer bundle.deinit() catch unreachable;
    var host = registry.PluginHost.init(a);
    defer host.deinit();
    for (bundle.renderers()) |renderer| try host.registerRenderer(renderer);
    for (bundle.manifests()) |manifest| try host.register(manifest);
    try T.expectError(error.MissingDependency, host.publish());
    var incompatible = linked.supported_apis;
    incompatible[incompatible.len - 1].major = 2;
    host.apis = &incompatible;
    try T.expectError(error.DependencyVersionMismatch, host.publish());
    host.apis = &linked.supported_apis;
    var published = try host.publish();
    defer published.deinit();

    var unsupported = bundle.manifests()[0];
    unsupported.dependencies = &.{.{ .id = "host.configuration" }};
    try T.expectError(error.MissingDependency, linked.initRegistry(a, &.{}, &.{unsupported}, bundle.renderers()));
}

test "BMC composition return by value keeps budget and durable journal contexts stable" {
    var tmp = T.tmpDir(.{});
    defer tmp.cleanup();
    const path = try tmp.dir.realPathFileAlloc(T.io, ".", a);
    defer a.free(path);
    var original = try composition.Bundle(false).init(a, T.io, path, &all_enabled);
    const plugin = pluginFor(&original);
    const budget = original.frameBudget();
    const backend = plugin.journal.backend;
    var moved = original;
    original = undefined;
    defer moved.deinit() catch unreachable;
    try T.expect(moved.frameBudget() == budget);
    try T.expect(pluginFor(&moved) == plugin);
    try T.expect(plugin.options.frame_budget == budget);
    const bytes = "{\"schema_version\":1,\"entries\":[]}";
    try backend.replace_durable(backend.context, bytes);
    const recovered = (try backend.read(backend.context, a)).?;
    defer a.free(recovered);
    try T.expectEqualStrings(bytes, recovered);
    const stat = try tmp.dir.statFile(T.io, "bmc-management-v1.json", .{});
    try T.expectEqual(@as(u16, 0o600), @as(u16, @intCast(@backingInt(stat.permissions) & 0o777)));
    try moved.deinit();
    try T.expect(moved.resources == null);
    try T.expectEqual(@as(usize, 0), moved.manifests().len);
}

fn unstartedRuntime(plugin: *bmc.Plugin, budget: *budgets.Budget) !*runtime_api.Runtime {
    const owner: identity.SessionHandle = .{ .session_id = @fromBackingInt(601) };
    const key: sessions.OperationKey = .{ .owner = .{ .session = owner }, .operation_id = 1 };
    const control = try controller.Controller.create(a, owner, key, .{ .endpoint = .{ .host = "bmc.invalid" }, .username = "fixture" }, null, budget, &plugin.journal, null);
    errdefer control.deinit() catch unreachable;
    const name = try a.dupe(u8, "BMC fixture");
    errdefer a.free(name);
    const endpoint = try a.dupe(u8, "bmc.invalid:443");
    errdefer a.free(endpoint);
    const route_summary = try a.dupe(u8, "本机 → bmc.invalid:443");
    errdefer a.free(route_summary);
    const runtime = try a.create(runtime_api.Runtime);
    runtime.* = .{ .allocator = a, .owner = owner, .operation = key, .context = .{ .owner = owner, .operation = key, .target = .{ .window_id = target.window_id, .workspace_id = target.workspace_id } }, .name = name, .target = endpoint, .route_summary = route_summary, .controller = control, .ai_control = @import("../ai_control.zig").Service.init(owner, &control.framebuffer, &control.remote_input), .bridge = runtime_api.ChallengeBridge.init(a, owner, key, null), .management_policy = .read_only };
    return runtime;
}

test "BMC composition retains the real resource owner for unknown cleanup and outstanding frame leases" {
    var tmp = T.tmpDir(.{});
    defer tmp.cleanup();
    const path = try tmp.dir.realPathFileAlloc(T.io, ".", a);
    defer a.free(path);
    var bundle = try composition.Bundle(false).init(a, T.io, path, &all_enabled);
    defer bundle.deinit() catch unreachable;
    const plugin = pluginFor(&bundle);
    const budget = bundle.frameBudget();
    const resources = bundle.resources;
    const runtime = try unstartedRuntime(plugin, budget);
    plugin.runtimes.append(a, runtime) catch |err| {
        try runtime.deinit();
        return err;
    };
    // Supply an already stopped controller's unknown receipt without starting
    // any detached worker or network IO in this composition test.
    runtime.stopping = true;
    runtime.controller.worker_exited.store(true, .release);
    runtime.controller.state.cleanup = .unknown;
    try T.expectError(error.BmcCleanupPending, bundle.deinit());
    try T.expect(bundle.resources == resources);
    try T.expect(pluginFor(&bundle) == plugin);
    try T.expect(bundle.frameBudget() == budget);

    runtime.controller.state.cleanup = .released;
    _ = try runtime.controller.framebuffer.publishComplete(1, 1, &.{ 1, 2, 3, 255 }, 1);
    var lease = runtime.controller.framebuffer.acquireLatest(runtime.controller.framebuffer.binding(), 0).frame;
    defer lease.release();
    try T.expectError(error.FrameBorrowed, bundle.deinit());
    try T.expect(bundle.resources == resources);
    try T.expectEqual(@as(usize, 4), budget.usedBytes());
    try T.expectEqualSlices(u8, &.{ 1, 2, 3, 255 }, lease.snapshot.pixels);
    lease.release();
    try bundle.deinit();
    try T.expect(bundle.resources == null);
}

const Fixture = struct {
    var context: u8 = 0;
    fn validate(_: []const u8) !void {}
    fn create(_: *anyopaque, _: sessions.CreateRequest) !void {}
    fn cancel(_: *anyopaque, _: sessions.OperationKey) sessions.CloseReceipt {
        return .released;
    }
    fn close(_: *anyopaque, _: identity.SessionHandle, _: sessions.OperationKey) !sessions.CloseReceipt {
        return .released;
    }
    fn stale(_: *anyopaque, _: identity.SessionHandle, _: sessions.OperationKey) void {}
    fn manifest(id: []const u8, limits: ?frames.Limits) registry.PluginManifest {
        return .{ .id = id, .display_name = id, .workspace_kind = "composition.canvas", .content_renderer = "composition.canvas", .frame_limits = limits, .quick_create = .{ .validate_payload = validate }, .session_factory = .{ .context = &context, .vtable = &.{ .create = create, .cancel = cancel, .close = close, .release_stale = stale } } };
    }
    fn textureCreate(_: *anyopaque, _: u32, _: u32) !u32 {
        return error.UnexpectedGraphicsCall;
    }
    fn textureUpdate(_: *anyopaque, _: u32, _: []const u8) !void {
        return error.UnexpectedGraphicsCall;
    }
    fn textureRelease(_: *anyopaque, _: u32) void {
        unreachable;
    }
    fn fullscreen(_: *anyopaque, _: bool) !void {}
    fn fullscreenState(_: *anyopaque) bool {
        return false;
    }
    fn transfer(_: *anyopaque, _: identity.SessionHandle, _: identity.WindowId) !void {}
};

test "BMC composition generic content uses manifest limits and shared budget while legacy stays unchanged" {
    const custom: frames.Limits = .{ .max_width = 3000, .max_height = 2000, .max_frame_bytes = 24 * 1024 * 1024 };
    var host = try sessions.SessionHost.initPlugins(a, &.{ Fixture.manifest("vendor.canvas", custom), Fixture.manifest("vendor.old", null) }, &.{.{ .kind = "composition.canvas", .shared_renderer = true }});
    defer host.deinit();
    const owner = try host.create(.{ .plugin = .{ .protocol_id = "vendor.canvas", .name = "Custom canvas", .payload = "{}" } }, target);
    const legacy = try host.create(.{ .plugin = .{ .protocol_id = "vendor.old", .name = "Legacy canvas", .payload = "{}" } }, target);
    var budget = budgets.Budget.init(budgets.application_bytes);
    defer budget.deinit() catch unreachable;
    const cx = try ui.Cx.init(a, T.io);
    defer cx.deinit();
    const content_host = try ContentHost.init(cx, target.window_id, .{ .context = &Fixture.context, .request_fullscreen = Fixture.fullscreen, .fullscreen_state = Fixture.fullscreenState, .transfer = Fixture.transfer }, .{ .context = &Fixture.context, .create = Fixture.textureCreate, .update = Fixture.textureUpdate, .release = Fixture.textureRelease });
    content_host.setSessionHost(&host);
    const factory = content_host.factory();
    try T.expectError(error.FrameBudgetUnavailable, factory.create(factory.context, owner.handle));
    try T.expectEqual(@as(usize, 0), content_host.entries.items.len);
    content_host.setFrameBudget(&budget);
    const configured = try factory.create(factory.context, owner.handle);
    try T.expect(configured.service_access != null);
    try T.expect(configured.service_access.?.owner.eql(owner.handle));
    try T.expect(configured.frame_sink.?.budget == &budget);
    try T.expectEqual(custom, configured.frame_sink.?.limits);
    const reused = try factory.create(factory.context, owner.handle);
    try T.expect(reused.frame_sink == configured.frame_sink);
    const unchanged = try factory.create(factory.context, legacy.handle);
    try T.expect(unchanged.frame_sink.?.budget == null);
    try T.expectEqual(budgets.default_frame_bytes, unchanged.frame_sink.?.limits.max_frame_bytes);
    try T.expectEqual(@as(u32, 8192), unchanged.frame_sink.?.limits.max_width);
    try T.expectError(error.InvalidFrame, unchanged.frame_sink.?.limits.byteLength(4096, 2160));
    try T.expectEqual(budgets.kvm_frame_bytes, try budgets.Limits.kvm.byteLength(4096, 2160));
}

test "BMC composition opens only the supplied existing data directory and refuses symlink redirects" {
    try T.expectError(error.InvalidPluginDataDirectory, composition.Bundle(false).init(a, T.io, "relative-data", &all_enabled));
    var tmp = T.tmpDir(.{});
    defer tmp.cleanup();
    const path = try tmp.dir.realPathFileAlloc(T.io, ".", a);
    defer a.free(path);
    const missing = try std.fs.path.join(a, &.{ path, "missing" });
    defer a.free(missing);
    try T.expectError(error.FileNotFound, composition.Bundle(false).init(a, T.io, missing, &all_enabled));
    try tmp.dir.createDir(T.io, "real", .default_dir);
    try tmp.dir.symLink(T.io, "real", "redirect", .{ .is_directory = true });
    const redirect = try std.fs.path.join(a, &.{ path, "redirect" });
    defer a.free(redirect);
    if (composition.Bundle(false).init(a, T.io, redirect, &all_enabled)) |value| {
        var unexpected = value;
        try unexpected.deinit();
        return error.SymlinkAccepted;
    } else |_| {}
}

test "BMC composition PL4a: plugin card types publish with the registry and carry the AI that the manifest used to declare (golden)" {
    var tmp = T.tmpDir(.{});
    defer tmp.cleanup();
    const path = try tmp.dir.realPathFileAlloc(T.io, ".", a);
    defer a.free(path);
    var acceptance = try composition.Bundle(true).init(a, T.io, path, &all_enabled);
    defer acceptance.deinit() catch unreachable;
    var published = try linked.initRegistry(a, &.{}, acceptance.manifests(), acceptance.renderers());
    defer published.deinit();
    // 改动前清单上的值：integration.ai = true、ai_context.identity 如下、没有 ai_adapter_factory。
    const Golden = struct { id: []const u8, card: []const u8, identity: []const u8 };
    const golden = [_]Golden{
        .{ .id = "bmc_ikvm", .card = "kvm", .identity = "BMC console with read-only management, approved remote-frame observation and exclusive bounded input" },
        .{ .id = "fixture_probe", .card = "fixture_probe", .identity = "Synthetic non-terminal fixture" },
    };
    for (golden) |item| {
        const manifest = published.find(item.id).?;
        const card = published.cardTypeFor(manifest).?;
        try T.expectEqualStrings(item.card, card.id);
        try T.expect(card.binding == .session and card.placements.standalone_tab and card.placements.split and card.placements.float);
        // cards-float：插件会话卡片也可浮动，放置动作由注册表推出（作为标签页打开、放入分屏都可用，没有收起）。
        const derived = registry.card_types.floatDescriptor(card).?;
        try T.expect(derived.supports(.open_as_tab) and derived.supports(.dock_to_split) and !derived.supports(.minimize));
        try T.expect(card.float.?.min_size.width >= 480 and card.float.?.min_size.height >= 300);
        const ai = card.ai.?;
        try T.expectEqualStrings(item.identity, ai.summary.provider.identity);
        try T.expect(ai.summary.provider.summarize != null);
        try T.expect(ai.engineFor(manifest.id) == null);
        // 自有工具 = 本插件登记的全部工具。
        try T.expectEqual(manifest.tools.len, ai.tools.own.len);
        for (manifest.tools, ai.tools.own) |binding, id| try T.expectEqualStrings(binding.definition_id, id);
    }
    // 内置类型与插件类型一起发布；没有运行期登记入口（Registry 只读）。
    for ([_][]const u8{ "terminal", "file", "session", "ai.chat", "history", "kvm", "fixture_probe" }) |id| try T.expect(published.cardType(id) != null);
    try T.expect(published.cardType("history.archive") == null); // PL4b H5：过渡的归档类型已删除
    try T.expect(!@hasDecl(registry.Registry, "registerCardType"));
}

test "BMC composition PL4a: card registration is validated before anything is published" {
    var host = registry.PluginHost.init(a);
    defer host.deinit();
    for (linked.builtinCardTypes()) |definition| try host.registerCardType(definition);
    try host.registerCardType(linked.builtinCardTypes()[0]);
    try T.expectError(error.DuplicateCardType, host.publish());

    var unknown = registry.PluginHost.init(a);
    defer unknown.deinit();
    for (linked.builtinCardTypes()) |definition| try unknown.registerCardType(definition);
    for (linked.shared_renderers) |renderer| try unknown.registerRenderer(renderer);
    const Factory = struct {
        var context: u8 = 0;
        fn create(_: *anyopaque, _: sessions.CreateRequest) !void {}
        fn cancel(_: *anyopaque, _: sessions.OperationKey) sessions.CloseReceipt {
            return .released;
        }
        fn close(_: *anyopaque, _: identity.SessionHandle, _: sessions.OperationKey) !sessions.CloseReceipt {
            return .released;
        }
        fn stale(_: *anyopaque, _: identity.SessionHandle, _: sessions.OperationKey) void {}
        const vtable: sessions.Adapter.VTable = .{ .create = create, .cancel = cancel, .close = close, .release_stale = stale };
    };
    var manifest: registry.PluginManifest = .{ .id = "probe", .display_name = "Probe", .workspace_kind = "terminal", .content_renderer = "terminal", .session_factory = .{ .context = &Factory.context, .vtable = &Factory.vtable }, .card_type = "missing" };
    try unknown.register(manifest);
    try T.expectError(error.UnknownCardType, unknown.publish());

    // 会话清单不能把会话呈现为非会话卡片（ai.chat 绑定 tab）。
    var tab_bound = registry.PluginHost.init(a);
    defer tab_bound.deinit();
    for (linked.builtinCardTypes()) |definition| try tab_bound.registerCardType(definition);
    for (linked.shared_renderers) |renderer| try tab_bound.registerRenderer(renderer);
    manifest.card_type = "ai.chat";
    try tab_bound.register(manifest);
    try T.expectError(error.CardTypeNotSessionBound, tab_bound.publish());

    // 插件卡片的自有工具必须是本插件登记的工具。
    var own = registry.PluginHost.init(a);
    defer own.deinit();
    for (linked.builtinCardTypes()) |definition| try own.registerCardType(definition);
    for (linked.shared_renderers) |renderer| try own.registerRenderer(renderer);
    manifest.card_type = "probe.card";
    manifest.cards = &.{.{ .id = "probe.card", .title = "Probe", .binding = .session, .placements = .{ .standalone_tab = true }, .default_placement = .standalone_tab, .ai = .{ .summary = .{ .provider = .{ .identity = "probe" } }, .tools = .{ .own = &.{"probe.missing"} } } }};
    try own.register(manifest);
    try T.expectError(error.UnknownCardTool, own.publish());
}
