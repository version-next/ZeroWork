//! 设置窗口“AI 辅助”面板的宿主侧（F-set-ai）：view-model 发的 `Effect.ai`（`ai_pane.Job`）在这里执行——获取模型清单、
//! 测试模型（`ai/model_discovery.zig` 的后台任务）、技能导入 / 查看、MCP 测试 / 网页登录（独立线程，旧
//! `view/ai_extensions_settings.zig` 的 `Job` 原样搬来）；结果经 `status()` 投影成 `HostStatus.ai`，`poll` 每帧收尾，
//! 有变化时返回 true（宿主随即 `vm.sync()`）。
//!
//! 与旧实现的差别只有位置：旧视图在自己的 after-layout 钩子里轮询、页面卸载时取消；现在宿主持有，离开页面不取消，
//! 关闭设置窗口时 `stop()` 取消全部任务。
const std = @import("std");
const applog = @import("../../../platform/applog.zig");
const config = @import("../../../config/config.zig");
const ext = @import("../../../config/ai_extensions.zig");
const Controller = @import("../model/settings_controller.zig").Controller;
const ai_pane = @import("../model/ai_pane.zig");
const draft = @import("../model/settings_ai_draft.zig");
const Discovery = @import("../../../ai/model_discovery.zig").Service;
const local = @import("../../../ai/local_skills.zig");
const mcp = @import("../../../ai/mcp_client.zig");
const oauth = @import("../../../ai/mcp_oauth.zig");
const Cancel = @import("../../../ai/provider.zig").CancelToken;

extern "c" fn zw_pick_skill_path([*]u8, c_int) c_int;

pub const AiJobs = struct {
    allocator: std.mem.Allocator,
    discovery: Discovery = .{},
    model_test: Discovery = .{},
    // ── 模型清单 ──
    catalog_provider: ?usize = null,
    catalog_signature: u64 = 0,
    catalog_revision: u64 = 0,
    catalog_message: []const u8 = "",
    catalog_detail: [1400]u8 = undefined,
    catalog_arena: ?std.heap.ArenaAllocator = null,
    catalog_models: []const config.AiModel = &.{},
    catalog_known: []const [2]bool = &.{},
    // ── 模型测试 ──
    test_signature: ?u64 = null,
    test_message: []const u8 = "",
    test_detail: [1200]u8 = undefined,
    provider_error: []const u8 = "",
    // ── 扩展任务 ──
    job: ?*Job = null,
    status_text: [1400]u8 = undefined,
    status_message: []const u8 = "",
    status_error: bool = false,
    status_mcp: bool = false,
    detail_buffer: std.ArrayList(u8) = .empty,
    detail_open: bool = false,
    detail_target: ai_pane.DetailTarget = .none,
    detail_ids: [2][160]u8 = undefined,
    results: [16]ai_pane.ServerResult = @splat(.{}),
    result_text: [16][256]u8 = undefined,
    result_ids: [16][96]u8 = undefined,
    result_details: [16]std.ArrayList(u8) = @splat(.empty),

    pub fn init(allocator: std.mem.Allocator) AiJobs {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *AiJobs) void {
        self.stop();
        self.discovery.deinit();
        self.model_test.deinit();
        if (self.catalog_arena) |*arena| arena.deinit();
        self.detail_buffer.deinit(self.allocator);
        for (&self.result_details) |*item| item.deinit(self.allocator);
        self.* = .{ .allocator = self.allocator };
    }
    /// 关闭设置窗口：取消进行中的获取 / 测试 / 扩展任务（等线程结束），清掉提示（清单与测试结果按旧实现随页面消失）。
    pub fn stop(self: *AiJobs) void {
        self.discovery.cancelRequest();
        self.model_test.cancelRequest();
        if (self.job) |job| {
            job.cancel.cancel();
            job.thread.?.join();
            job.destroy();
            self.job = null;
        }
        while (self.discovery.busy() and !self.discovery.finishRequest()) std.Thread.yield() catch {};
        while (self.model_test.busy() and !self.model_test.finishRequest()) std.Thread.yield() catch {};
        self.catalog_provider = null;
        self.catalog_message = "";
        self.test_signature = null;
        self.test_message = "";
        self.provider_error = "";
        self.status_message = "";
        self.status_error = false;
        self.detail_open = false;
        self.detail_target = .none;
    }
    pub fn busy(self: *const AiJobs) bool {
        return self.discovery.busy() or self.model_test.busy() or self.job != null;
    }
    /// 扩展任务进行中（导航 / 搜索 / 保存的关口拒绝，同旧 `extensions_view.busy()`）。
    pub fn extensionBusy(self: *const AiJobs) bool {
        return self.job != null;
    }

    pub fn status(self: *const AiJobs) ai_pane.HostAi {
        return .{
            .catalog_provider = self.catalog_provider,
            .catalog_signature = self.catalog_signature,
            .catalog_busy = self.discovery.busy(),
            .catalog_message = self.catalog_message,
            .catalog_models = self.catalog_models,
            .catalog_known = self.catalog_known,
            .test_busy = self.model_test.busy(),
            .test_message = self.test_message,
            .test_signature = self.test_signature,
            .job_busy = self.job != null,
            .status = self.status_message,
            .status_error = self.status_error,
            .status_mcp = self.status_mcp,
            .detail = self.detail_buffer.items,
            .detail_open = self.detail_open,
            .detail_target = self.detail_target,
            .server_results = &self.results,
            .provider_error = self.provider_error,
        };
    }

    /// 执行 view-model 发来的一件事。`data_root` 是应用数据目录（技能导入 / 读取）。
    pub fn run(self: *AiJobs, c: *Controller, data_root: []const u8, job: ai_pane.Job) void {
        switch (job) {
            .fetch_models => |index| self.fetchModels(c, index),
            .test_model => |request| {
                if (self.model_test.busy()) {
                    self.model_test.cancelRequest();
                    return;
                }
                if (request.provider >= c.model.value.ai.provider_count) return;
                self.test_signature = request.signature;
                self.model_test.testModel(c.model.value.ai.providers[request.provider], request.model) catch {
                    self.test_message = "无法开始测试，请检查配置。";
                    return;
                };
                self.test_message = "测试中…";
            },
            .cancel_test => self.model_test.cancelRequest(),
            .pick_skill => |index| {
                var buffer: [4096]u8 = undefined;
                const length = zw_pick_skill_path(&buffer, @intCast(buffer.len));
                if (length < 0) return self.fail(error.FilePickerUnavailable, false);
                if (length == 0) return;
                self.start(c, data_root, .import_skill, index, buffer[0..@intCast(length)]) catch |err| self.fail(err, false);
            },
            .import_skill => |path| self.start(c, data_root, .import_skill, null, path) catch |err| self.fail(err, false),
            .read_skill => |index| self.start(c, data_root, .read, index, "") catch |err| self.fail(err, false),
            .test_server => |index| self.start(c, data_root, .test_connection, index, "") catch |err| self.fail(err, true),
            .authorize_server => |index| self.start(c, data_root, .authorize, index, "") catch |err| self.fail(err, true),
            .logout_server => |index| {
                const servers = c.model.value.ai.extensions.servers;
                if (index < servers.len) oauth.logout(servers[index]);
                self.message("", true);
            },
            .cancel_job => if (self.job) |active| active.cancel.cancel(),
            .close_detail => self.detail_open = false,
            .show_server_detail => |index| {
                const servers = c.model.value.ai.extensions.servers;
                if (index >= servers.len or index >= self.results.len) return;
                const result = self.results[index];
                if (result.failed or !std.mem.eql(u8, result.id, servers[index].id) or result.revision != servers[index].revision) return;
                self.detail_buffer.clearRetainingCapacity();
                self.detail_buffer.appendSlice(self.allocator, self.result_details[index].items) catch {};
                self.detail_target = .{ .server = .{ .id = result.id, .revision = result.revision } };
                self.detail_open = true;
            },
        }
    }

    fn fetchModels(self: *AiJobs, c: *Controller, index: usize) void {
        if (self.discovery.busy()) {
            self.discovery.cancelRequest();
            self.catalog_message = "正在取消获取…";
            return;
        }
        const ai = c.model.value.ai;
        if (index >= ai.provider_count) return;
        const p = ai.providers[index];
        self.catalog_provider = index;
        self.catalog_signature = ai_pane.connectionSignature(p);
        self.catalog_revision +|= 1;
        self.discovery.request(p, self.catalog_revision) catch {
            self.provider_error = "无法开始获取模型清单，请重试。";
            self.catalog_message = "";
            return;
        };
        self.provider_error = "";
        self.catalog_message = "正在获取模型清单…";
    }

    /// 每帧收尾（主线程）：后台任务结束了就发布结果。返回 true 表示状态变了（宿主 `vm.sync()`）；仍在进行时宿主要继续排帧。
    pub fn poll(self: *AiJobs, c: *Controller) bool {
        var changed = false;
        if (self.model_test.busy() and self.model_test.finishRequest()) {
            self.test_message = if (self.model_test.request_error) |err| (if (err == error.Cancelled) "测试已取消" else self.model_test.diagnostic.format(&self.test_detail, err)) else "模型请求已完成。";
            changed = true;
        }
        if (self.discovery.busy() and self.discovery.finishRequest()) {
            self.publishCatalog(c);
            changed = true;
        }
        if (self.job) |job| {
            if (job.done.load(.acquire)) {
                job.thread.?.join();
                self.job = null;
                defer job.destroy();
                self.finishJob(c, job);
                changed = true;
            } else if (job.browser_pending.swap(false, .acq_rel)) {
                const Native = struct {
                    extern fn macos_open_url([*:0]const u8) c_int;
                };
                if (job.arena.allocator().dupeSentinel(u8, job.browser_url, 0)) |url| {
                    job.browser_result.store(if (Native.macos_open_url(url) == 1) 1 else -1, .release);
                } else |_| job.browser_result.store(-1, .release);
            }
        }
        return changed;
    }

    fn publishCatalog(self: *AiJobs, c: *Controller) void {
        const ai = c.model.value.ai;
        const valid = if (self.catalog_provider) |i| i < ai.provider_count and self.catalog_signature == ai_pane.connectionSignature(ai.providers[i]) else false;
        if (self.catalog_arena) |*arena| arena.deinit();
        self.catalog_arena = std.heap.ArenaAllocator.init(self.allocator);
        self.catalog_models = &.{};
        self.catalog_known = &.{};
        const effective = self.discovery.effective(.{}, self.catalog_revision);
        const models: []const config.AiModel = if (effective.provider_count > 0) effective.providers[0].models[0..effective.providers[0].model_count] else &.{};
        if (self.discovery.request_error == null) copy: {
            const a = self.catalog_arena.?.allocator();
            const owned = a.alloc(config.AiModel, models.len) catch break :copy;
            const known = a.alloc([2]bool, models.len) catch break :copy;
            for (models, owned, known) |model, *dst, *flags| {
                dst.* = model;
                dst.id = a.dupe(u8, model.id) catch "";
                const metadata = self.discovery.modelMetadata(model.id);
                flags.* = if (metadata) |value| .{ value.reasoning_known, value.vision_known } else .{ false, false };
            }
            self.catalog_models = owned;
            self.catalog_known = known;
        }
        self.catalog_message = if (!valid) "连接配置已变化，请重新获取模型清单。" else if (self.discovery.request_error) |err| switch (err) {
            error.Cancelled => "已取消获取；可重新获取或手动添加模型。",
            error.InvalidCatalog => "接口未提供有效模型清单，可手动添加模型。",
            else => self.discovery.diagnostic.format(&self.catalog_detail, err),
        } else if (self.catalog_models.len == 0) "接口未返回模型，可重新获取或手动添加。" else "模型清单已获取，添加模型时可下拉选择。";
    }

    fn message(self: *AiJobs, content: []const u8, mcp_area: bool) void {
        const n = @min(content.len, self.status_text.len);
        @memcpy(self.status_text[0..n], content[0..n]);
        self.status_message = self.status_text[0..n];
        self.status_error = false;
        self.status_mcp = mcp_area;
    }
    fn fail(self: *AiJobs, err: anyerror, mcp_area: bool) void {
        applog.warn(.ui, "ai extension operation failed: {s}", .{@errorName(err)});
        self.message(ai_pane.extensionError(err), mcp_area);
        self.status_error = true;
    }
    fn start(self: *AiJobs, c: *Controller, root: []const u8, kind: Job.Kind, index: ?usize, path: []const u8) !void {
        if (self.job != null or c.state() == .saving) return error.SettingsBusy;
        const mcp_job = kind == .test_connection or kind == .authorize;
        if (index) |i| {
            const limit = if (mcp_job) c.model.value.ai.extensions.servers.len else c.model.value.ai.extensions.skills.len;
            if (i >= limit) return error.SettingsBusy;
        }
        self.status_message = "";
        self.status_error = false;
        self.status_mcp = mcp_job;
        // 重新测试 / 授权一个正展开的服务：先收起详情（旧 `start`）。
        if (mcp_job) if (self.detail_target == .server) {
            self.detail_open = false;
        };
        const job = try Job.create(c, root, kind, index, path);
        errdefer job.destroy();
        job.thread = try std.Thread.spawn(.{}, Job.run, .{job});
        self.job = job;
    }
    /// 旧 `View.afterLayout` 的收尾分支：测试结果、草稿已变化、失败、导入写回草稿、读取 SKILL.md。
    fn finishJob(self: *AiJobs, c: *Controller, job: *Job) void {
        self.status_mcp = job.mcpJob();
        if (job.problem) |err| applog.warn(.ui, "ai extension job failed: {s}", .{@errorName(err)});
        if (job.mcpJob() and job.draft_id == c.draft_id) {
            const i = job.index.?;
            if (i < self.results.len) {
                const server = job.frozen.servers[i];
                const label = if (job.problem) |err| (if (job.output.len != 0) job.output else ai_pane.extensionError(err)) else job.summary;
                const id_len = @min(server.id.len, self.result_ids[i].len);
                @memcpy(self.result_ids[i][0..id_len], server.id[0..id_len]);
                const label_len = @min(label.len, self.result_text[i].len);
                @memcpy(self.result_text[i][0..label_len], label[0..label_len]);
                self.results[i] = .{ .id = self.result_ids[i][0..id_len], .revision = server.revision, .label = self.result_text[i][0..label_len], .failed = job.problem != null };
                self.result_details[i].clearRetainingCapacity();
                if (job.problem == null) self.result_details[i].appendSlice(self.allocator, job.output) catch {};
            }
        }
        if (job.draft_id != c.draft_id or c.state() == .saving) {
            self.message("设置草稿已变化，本次结果已丢弃。", job.mcpJob());
            self.status_error = true;
            return;
        }
        if (job.problem) |err| {
            if (job.output.len != 0) self.message(job.output, job.mcpJob()) else self.fail(err, job.mcpJob());
            self.status_error = true;
            return;
        }
        if (job.imported.items.len != 0) {
            var extensions = c.model.value.ai.extensions;
            var list: std.ArrayList(ext.Skill) = .empty;
            defer list.deinit(self.allocator);
            list.appendSlice(self.allocator, extensions.skills) catch return;
            if (job.index) |i| {
                if (i >= list.items.len or !std.mem.eql(u8, list.items[i].id, job.frozen.skills[i].id)) {
                    self.message("技能选择已变化，请重新导入。", false);
                    self.status_error = true;
                    return;
                }
                list.items[i] = job.imported.items[0].skill;
            } else for (job.imported.items) |imported| list.append(self.allocator, imported.skill) catch return;
            extensions.skills = list.items;
            c.setExtensions(extensions) catch |err| return self.fail(err, false);
            self.message("", false);
        } else if (job.kind == .read) {
            const skill = job.frozen.skills[job.index.?];
            self.detail_buffer.clearRetainingCapacity();
            self.detail_buffer.appendSlice(self.allocator, job.output) catch {};
            const id_len = @min(skill.id.len, self.detail_ids[0].len);
            const revision_len = @min(skill.revision.len, self.detail_ids[1].len);
            @memcpy(self.detail_ids[0][0..id_len], skill.id[0..id_len]);
            @memcpy(self.detail_ids[1][0..revision_len], skill.revision[0..revision_len]);
            self.detail_target = .{ .skill = .{ .id = self.detail_ids[0][0..id_len], .revision = self.detail_ids[1][0..revision_len] } };
            self.detail_open = true;
            self.message("", false);
        } else self.message("", job.mcpJob());
    }
};

/// 扩展的后台任务（旧 `ai_extensions_settings.Job`，逐行搬来，行为不变）。
const Job = struct {
    const Kind = enum { import_skill, read, test_connection, authorize };
    browser_pending: std.atomic.Value(bool) = .init(false),
    browser_result: std.atomic.Value(i32) = .init(0),
    browser_url: []const u8 = "",
    arena: std.heap.ArenaAllocator,
    frozen: ext.Extensions,
    root: []const u8,
    path: []const u8,
    kind: Kind,
    index: ?usize,
    draft_id: u64,
    thread: ?std.Thread = null,
    cancel: Cancel = .{},
    done: std.atomic.Value(bool) = .init(false),
    problem: ?anyerror = null,
    imported: std.ArrayList(local.Imported) = .empty,
    diagnostic: local.Diagnostic = .{},
    active_path: []const u8 = "",
    output: []const u8 = "",
    summary: []const u8 = "",
    fn mcpJob(self: *const Job) bool {
        return self.kind == .test_connection or self.kind == .authorize;
    }
    fn openBrowser(raw: *anyopaque, url: []const u8) !void {
        const self: *Job = @ptrCast(@alignCast(raw));
        self.browser_url = try self.arena.allocator().dupe(u8, url);
        self.browser_pending.store(true, .release);
        while (self.browser_result.load(.acquire) == 0) {
            try @import("../../../ai/retry.zig").wait(10, &self.cancel);
        }
        if (self.browser_result.load(.acquire) < 0) return error.BrowserOpenFailed;
    }
    fn create(c: *Controller, root: []const u8, kind: Kind, index: ?usize, path: []const u8) !*Job {
        const a = std.heap.c_allocator;
        const job = try a.create(Job);
        errdefer a.destroy(job);
        var arena = std.heap.ArenaAllocator.init(a);
        errdefer arena.deinit();
        job.* = .{ .arena = arena, .frozen = try c.model.value.ai.extensions.clone(arena.allocator()), .root = try arena.allocator().dupe(u8, root), .path = try arena.allocator().dupe(u8, path), .kind = kind, .index = index, .draft_id = c.draft_id };
        return job;
    }
    fn destroy(self: *Job) void {
        for (self.imported.items) |*imported| imported.deinit();
        self.imported.deinit(self.arena.allocator());
        for (self.frozen.servers) |server| inline for (.{ "environment", "headers" }) |key| for (@field(server, key)) |entry| if (entry.secret) {
            std.crypto.secureZero(u8, @constCast(entry.value));
        };
        self.arena.deinit();
        std.heap.c_allocator.destroy(self);
    }
    fn run(self: *Job) void {
        self.execute() catch |err| {
            self.problem = err;
            if (!self.mcpJob() and self.active_path.len != 0) {
                const reason = ai_pane.extensionError(err);
                self.output = std.fmt.allocPrint(self.arena.allocator(), "{s}\n{s}{s}{s}", .{ reason, self.active_path, if (self.diagnostic.path_len != 0) "/" else "", self.diagnostic.path[0..self.diagnostic.path_len] }) catch reason;
            }
        };
        self.done.store(true, .release);
    }
    fn execute(self: *Job) !void {
        var io_threaded: std.Io.Threaded = .init(std.heap.c_allocator, .{});
        defer io_threaded.deinit();
        const io = io_threaded.io();
        const a = self.arena.allocator();
        if (self.cancel.isCancelled()) return error.Cancelled;
        switch (self.kind) {
            .import_skill => {
                const dir = try std.Io.Dir.cwd().openDir(io, self.root, .{});
                defer dir.close(io);
                self.active_path = self.path;
                const paths = try local.sources(a, io, self.path);
                if (self.index != null and paths.len != 1) return error.SkillReplaceCollection;
                for (paths) |path| {
                    if (self.cancel.isCancelled()) return error.Cancelled;
                    self.active_path = path;
                    var imported = try local.importLocalCancellable(std.heap.c_allocator, io, dir, path, if (self.index) |i| self.frozen.skills[i] else null, &self.diagnostic, &self.cancel);
                    errdefer imported.deinit();
                    for (self.frozen.skills, 0..) |prior, i| {
                        if (self.index != null and self.index.? == i) continue;
                        if (std.mem.eql(u8, prior.name, imported.skill.name)) return error.DuplicateSkill;
                    }
                    for (self.imported.items) |prior| if (std.mem.eql(u8, prior.skill.name, imported.skill.name)) return error.DuplicateSkill;
                    try self.imported.append(a, imported);
                }
            },
            .read => {
                const dir = try std.Io.Dir.cwd().openDir(io, self.root, .{});
                defer dir.close(io);
                self.active_path = self.frozen.skills[self.index.?].name;
                self.output = try local.readDiagnostic(a, io, dir, self.frozen.skills[self.index.?], "SKILL.md", &self.diagnostic);
            },
            .test_connection, .authorize => {
                if (self.kind == .authorize) try oauth.login(a, io, self.frozen.servers[self.index.?], .{ .context = self, .open = openBrowser }, &self.cancel);
                var client = try mcp.Client.init(std.heap.c_allocator, self.frozen.servers[self.index.?]);
                defer client.deinit();
                client.discover(&self.cancel) catch |err| {
                    if (client.rpc_error.len != 0) self.output = try std.fmt.allocPrint(a, "MCP 服务返回错误：{s}", .{client.rpc_error});
                    return err;
                };
                var out: std.Io.Writer.Allocating = .init(a);
                defer out.deinit();
                self.summary = try std.fmt.allocPrint(a, "MCP {s} · {d} 个工具", .{ client.negotiated_version, client.tools.items.len });
                try out.writer.print("{s} · MCP {s} · {d} 个工具\n", .{ self.frozen.servers[self.index.?].name, client.negotiated_version, client.tools.items.len });
                for (client.tools.items) |tool| try out.writer.print("{s} · {s}\n", .{ tool.name, if (tool.available) "可用" else tool.reason });
                self.output = try a.dupe(u8, out.written());
            },
        }
        if (self.cancel.isCancelled()) return error.Cancelled;
    }
};
