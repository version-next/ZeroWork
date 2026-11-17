//! M10 降级核对的夹具（ai-followup，PLUGIN_ARCH_PLAN 5.4 发布说明）。
//!
//! `test_fixtures/m10_downgrade/` 里是一次真实的"升级后再降级"现场：
//! - `ai-sessions.jsonl`：前两行由 M10 之前的版本（4fc8c181）写出（schema ≤ 3，归属 `.session`），
//!   之后的行由本版本追加（schema 4，归属 `.tab`）；
//! - `ai/lifecycle.json`：本版本写出的执行日志（`schema_version` 3，含 tab 绑定）。
//! 旧版本读它们的结果（`InvalidSessionJournal` / `UnsupportedJournalSchema`，只影响 AI，不影响启动）
//! 在临时 worktree 里用旧代码的单测核对过，结论与证据位置见发布说明。这里固定两件事：本版本能
//! 完整读回这些文件（新旧对话都在）；夹具的格式就是本版本今天写出的格式（行首 schema 与文件版本）。
//!
//! 重新生成：设置 `ZW_DOWNGRADE_OLD`（旧版本写出的日志）与 `ZW_DOWNGRADE_OUT`（输出目录）后运行
//! `zig build test -Dtest-filter="M10 downgrade fixture"`。
const std = @import("std");
const attached = @import("../attached_service.zig");
const lifecycle_journal = @import("../lifecycle_journal.zig");
const identity = @import("../../host/identity.zig");
const a = std.testing.allocator;
const io = std.testing.io;

const sessions_fixture = @embedFile("../test_fixtures/m10_downgrade/ai-sessions.jsonl");
const lifecycle_fixture = @embedFile("../test_fixtures/m10_downgrade/lifecycle.json");

test "M10 downgrade fixture: this version reads the mixed session journal and keeps the pre-upgrade conversation" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "ai-sessions.jsonl", .data = sessions_fixture });
    const path = try std.fmt.allocPrint(a, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer a.free(path);
    var host = attached.Host.init(a);
    defer host.deinit() catch unreachable;
    try host.ensurePersistence(path);
    try std.testing.expect(host.persistence_failure == null);
    var old_owner = false;
    var tab_owner = false;
    for (host.service.store.records.items) |record| {
        const origin = record.initial_origin orelse return error.MissingConversationOrigin;
        if (origin == .session) old_owner = true;
        if (origin == .tab) tab_owner = true;
    }
    try std.testing.expect(old_owner and tab_owner);
    // 夹具的行首格式：旧版本的行是 schema ≤ 3，本版本追加的行都是 schema 4。
    var lines = std.mem.splitScalar(u8, sessions_fixture, '\n');
    var old_lines: usize = 0;
    var new_lines: usize = 0;
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "{\"schema\":4,")) new_lines += 1 else old_lines += 1;
    }
    try std.testing.expect(old_lines != 0 and new_lines != 0);
}

test "M10 downgrade fixture: this version opens the tab-bound execution journal" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "ai");
    try tmp.dir.writeFile(io, .{ .sub_path = "ai/lifecycle.json", .data = lifecycle_fixture });
    var journal = try lifecycle_journal.Journal.open(a, io, tmp.dir, "ai/lifecycle.json");
    defer journal.deinit();
    try std.testing.expect(std.mem.startsWith(u8, lifecycle_fixture, "{\"schema_version\":3,"));
    try std.testing.expect(std.mem.indexOf(u8, lifecycle_fixture, "\"binding\":{\"tab\":") != null);
}

test "M10 downgrade fixture: regenerate from an old-version journal" {
    const old_path = if (std.c.getenv("ZW_DOWNGRADE_OLD")) |value| std.mem.span(value) else return error.SkipZigTest;
    const out = if (std.c.getenv("ZW_DOWNGRADE_OUT")) |value| std.mem.span(value) else return error.SkipZigTest;
    const old = try std.Io.Dir.cwd().readFileAlloc(io, old_path, a, .limited(16 * 1024 * 1024));
    defer a.free(old);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "ai-sessions.jsonl", .data = old });
    const path = try std.fmt.allocPrint(a, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer a.free(path);
    {
        // 升级后：旧对话照常回放（只读的 `.session` 归属），新对话绑定到 tab。
        var host = attached.Host.init(a);
        defer host.deinit() catch unreachable;
        try host.ensurePersistence(path);
        const agent = try host.service.store.attach(.{ .tab = 42 });
        const ticket = try host.service.store.create(agent.id);
        try host.service.store.checkpoint(ticket, 1, &.{ .{ .content = "new question after upgrade" }, .{ .role = .assistant, .content = "new answer after upgrade" } }, true);
    }
    {
        var journal = try lifecycle_journal.Journal.open(a, io, tmp.dir, "ai/lifecycle.json");
        defer journal.deinit();
        const request: lifecycle_journal.Request = .{ .context = .{ .conversation_id = identity.ConversationId.generate(), .task_id = identity.TaskId.generate(), .binding = .{ .tab = 42 }, .content = .{ .session = 7 }, .binding_revision = 1, .grant_revision = 1 }, .tool_id = "host.create_group", .request_key = "downgrade-fixture-1", .canonical_hash = @splat(4), .turn_id = 1, .call_id = "downgrade-fixture-call-1" };
        const handle = try journal.begin(request);
        try journal.update(handle, 1, .{ .stage = .committed, .created_group = 3, .committed_binding = .{ .tab = 43 }, .committed_binding_revision = 2, .notice_revision = 2 });
    }
    for ([_][]const u8{ "ai-sessions.v4.jsonl", "ai/lifecycle.json" }, [_][]const u8{ "ai-sessions.jsonl", "lifecycle.json" }) |source, name| {
        const bytes = try tmp.dir.readFileAlloc(io, source, a, .unlimited);
        defer a.free(bytes);
        const target = try std.fmt.allocPrint(a, "{s}/{s}", .{ out, name });
        defer a.free(target);
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = target, .data = bytes });
    }
}

// ---- 降级兼容（ai-bugs）：新版本只写 v4 文件名，旧文件首次启动时"读旧写新"，之后原样保留 ----

/// The rows written before M10 (schema ≤ 3): what an older version can still read.
fn preM10Rows() ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(a);
    var lines = std.mem.splitScalar(u8, sessions_fixture, '\n');
    while (lines.next()) |line| {
        if (line.len == 0 or std.mem.startsWith(u8, line, "{\"schema\":4,")) continue;
        try out.appendSlice(a, line);
        try out.append(a, '\n');
    }
    return out.toOwnedSlice(a);
}

test "M10 downgrade: the session journal migrates once to its v4 file and the legacy file stays byte-identical" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const legacy = try preM10Rows();
    defer a.free(legacy);
    try tmp.dir.writeFile(io, .{ .sub_path = "ai-sessions.jsonl", .data = legacy });
    const path = try std.fmt.allocPrint(a, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer a.free(path);
    var created: identity.ConversationId = undefined;
    {
        var host = attached.Host.init(a);
        defer host.deinit() catch unreachable;
        try host.ensurePersistence(path);
        // Read old: the pre-upgrade conversation is there.
        var old_owner = false;
        for (host.service.store.records.items) |record| {
            if ((record.initial_origin orelse return error.MissingConversationOrigin) == .session) old_owner = true;
        }
        try std.testing.expect(old_owner);
        // Write new: a tab-bound (schema 4) conversation.
        const agent = try host.service.store.attach(.{ .tab = 42 });
        const ticket = try host.service.store.create(agent.id);
        created = ticket.conversation;
        try host.service.store.checkpoint(ticket, 1, &.{ .{ .content = "after upgrade" }, .{ .role = .assistant, .content = "answer" } }, true);
    }
    const kept = try tmp.dir.readFileAlloc(io, "ai-sessions.jsonl", a, .unlimited);
    defer a.free(kept);
    try std.testing.expectEqualStrings(legacy, kept);
    try std.testing.expect(std.mem.indexOf(u8, kept, "{\"schema\":4,") == null);
    const current = try tmp.dir.readFileAlloc(io, "ai-sessions.v4.jsonl", a, .unlimited);
    defer a.free(current);
    try std.testing.expect(std.mem.startsWith(u8, current, legacy));
    try std.testing.expect(std.mem.indexOf(u8, current, "{\"schema\":4,") != null);
    // Later starts read only the v4 file: an older version's later writes to the legacy file
    // (here: one it cannot parse either way) do not reach this version.
    try tmp.dir.writeFile(io, .{ .sub_path = "ai-sessions.jsonl", .data = "{\"schema\":255}\n" });
    var reopened = attached.Host.init(a);
    defer reopened.deinit() catch unreachable;
    try reopened.ensurePersistence(path);
    try std.testing.expect(reopened.persistence_failure == null);
    try std.testing.expect(reopened.service.store.find(created) != null);
}

test "M10 downgrade: the execution journal migrates once to its v4 file and the legacy file stays byte-identical" {
    const runtime = @import("../lifecycle_runtime.zig");
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "ai");
    try tmp.dir.writeFile(io, .{ .sub_path = "ai/lifecycle.json", .data = lifecycle_fixture });
    const root = try tmp.dir.realPathFileAlloc(io, ".", a);
    defer a.free(root);
    const request: lifecycle_journal.Request = .{ .context = .{ .conversation_id = identity.ConversationId.generate(), .task_id = identity.TaskId.generate(), .binding = .{ .tab = 42 }, .content = .{ .session = 7 }, .binding_revision = 1, .grant_revision = 1 }, .tool_id = "host.create_group", .request_key = "downgrade-migration-1", .canonical_hash = @splat(5), .turn_id = 1, .call_id = "downgrade-migration-call-1" };
    {
        const owner = try runtime.ProcessJournal.acquire(.{ .data_root = root, .dir = tmp.dir, .io = io });
        defer owner.release();
        _ = try owner.begin(request);
    }
    const kept = try tmp.dir.readFileAlloc(io, "ai/lifecycle.json", a, .unlimited);
    defer a.free(kept);
    try std.testing.expectEqualStrings(lifecycle_fixture, kept);
    var migrated = try lifecycle_journal.Journal.open(a, io, tmp.dir, "ai/lifecycle.v4.json");
    defer migrated.deinit();
    var original = try lifecycle_journal.Journal.open(a, io, tmp.dir, "ai/lifecycle.json");
    defer original.deinit();
    // Read old, write new: every legacy operation plus the new one.
    try std.testing.expectEqual(original.records.items.len + 1, migrated.records.items.len);
}
