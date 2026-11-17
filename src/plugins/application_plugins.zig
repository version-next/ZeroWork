//! Production contributions are always present. Only this composition root
//! selects the additional acceptance fixture.
const std = @import("std");
const registry = @import("../host/plugin_registry.zig");
const presentation = @import("../host/plugin_ui_contract.zig");
const frames = @import("../host/frame_budget.zig");
const bmc = @import("bmc_ikvm/plugin.zig");
const ledger = @import("bmc_ikvm/management_journal.zig");
const enablement = @import("../host/plugin_enablement.zig");

pub fn Bundle(comptime acceptance_plugins: bool) type {
    return struct {
        const Self = @This();
        const Fixture = @import("fixture_probe/plugin.zig").Plugin;
        /// “已链接插件表”（PLUGIN_ARCH_PLAN 6.2.1 Q5 / PL1 第 6 条）：不初始化插件就能读到的元数据，
        /// 全仓只有这里按 ID 列举随应用提供的插件。
        pub const linked = [_]enablement.Linked{bmc.Plugin.linked} ++ (if (acceptance_plugins) [_]enablement.Linked{Fixture.linked} else [_]enablement.Linked{});
        const capacity = linked.len;
        const Resources = struct {
            allocator: std.mem.Allocator,
            io: std.Io,
            directory: std.Io.Dir,
            frame_budget: frames.Budget = frames.Budget.init(frames.application_bytes),
            journal_backend: ledger.FileBackend,
            plugin: ?*bmc.Plugin = null,
            fixture: if (acceptance_plugins) ?*Fixture else void = if (acceptance_plugins) null else {},
        };

        // Backend contexts and reservations borrow Resources, never this
        // return-by-value Bundle. Moving the Bundle cannot invalidate them.
        resources: ?*Resources,
        manifest_entries: [capacity]registry.PluginManifest = undefined,
        renderer_entries: [capacity]presentation.RendererDefinition = undefined,
        count: usize = 0,

        /// 被禁用的随应用插件（`launch.isEnabled(id) == false`）不初始化、不交给注册表（Q5）：不调它的 `init`，
        /// 不打开它自己的数据文件（bmc 的 `bmc-management-v1.json` 只在 init 里经 journal 读写），也不删除。
        pub fn init(allocator: std.mem.Allocator, io: std.Io, data_directory: []const u8, launch: *const enablement.Launch) !Self {
            const resources = try allocator.create(Resources);
            errdefer allocator.destroy(resources);
            const directory = try openDataDirectory(io, data_directory);
            errdefer directory.close(io);
            resources.* = .{
                .allocator = allocator,
                .io = io,
                .directory = directory,
                .journal_backend = .{ .io = io, .dir = directory, .filename = "bmc-management-v1.json" },
            };
            var self: Self = .{ .resources = resources };
            if (launch.isEnabled(bmc.Plugin.linked.id)) {
                const plugin = try bmc.Plugin.init(allocator, .{ .frame_budget = &resources.frame_budget, .journal_backend = try resources.journal_backend.backend() });
                resources.plugin = plugin;
                self.append(plugin.manifest(), plugin.renderer());
            }
            // init has not exposed a factory or started a worker yet.
            errdefer if (resources.plugin) |plugin| plugin.deinit() catch unreachable;
            if (comptime acceptance_plugins) if (launch.isEnabled(Fixture.linked.id)) {
                const fixture = try Fixture.init(allocator);
                resources.fixture = fixture;
                self.append(fixture.manifest(), fixture.renderer());
            };
            return self;
        }
        fn append(self: *Self, manifest: registry.PluginManifest, renderer: presentation.RendererDefinition) void {
            self.manifest_entries[self.count] = manifest;
            self.renderer_entries[self.count] = renderer;
            self.count += 1;
        }
        pub fn manifests(self: *const Self) []const registry.PluginManifest {
            return if (self.resources != null) self.manifest_entries[0..self.count] else &.{};
        }
        pub fn renderers(self: *const Self) []const presentation.RendererDefinition {
            return if (self.resources != null) self.renderer_entries[0..self.count] else &.{};
        }
        pub fn frameBudget(self: *Self) *frames.Budget {
            return &self.resources.?.frame_budget;
        }
        /// Pending/unknown cleanup retains the actual resource owner, including
        /// the plugin and its borrowed journal/budget, for a later drain/retry.
        pub fn deinit(self: *Self) !void {
            const resources = self.resources orelse return;
            if (resources.plugin) |plugin| {
                try plugin.deinit();
                resources.plugin = null;
            }
            try resources.frame_budget.deinit();
            if (comptime acceptance_plugins) if (resources.fixture) |fixture| fixture.deinit();
            resources.directory.close(resources.io);
            const allocator = resources.allocator;
            allocator.destroy(resources);
            self.resources = null;
        }
    };
}

/// Startup already prepares the application-owned private data directory.
/// Open the existing path component by component so a symlink cannot redirect
/// the durable journal. Composition never creates a fallback HOME directory.
fn openDataDirectory(io: std.Io, path: []const u8) !std.Io.Dir {
    if (!std.fs.path.isAbsolute(path) or std.mem.trim(u8, path, "/").len == 0) return error.InvalidPluginDataDirectory;
    var current = try std.Io.Dir.openDirAbsolute(io, "/", .{ .follow_symlinks = false });
    errdefer current.close(io);
    var components = std.mem.tokenizeScalar(u8, path, '/');
    while (components.next()) |component| {
        if (std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..")) return error.InvalidPluginDataDirectory;
        const next = try current.openDir(io, component, .{ .follow_symlinks = false });
        current.close(io);
        current = next;
    }
    return current;
}
