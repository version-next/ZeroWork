//! 持久化"读旧写新"基准（persist-async）。
//!
//! `config/test_fixtures/persist_compat/` 里的每个文件都由**引入共享持久化模块之前**的代码写出
//! （feat/ui-arch-revamp @ 9317f8df，用本文件末尾的再生成测试）。这里固定两件事：
//! 1. 读旧：当前代码能读出这些旧文件，读到的内容与写入时的输入一致；
//! 2. 写新：当前代码用同样的输入写出的文件与旧文件逐字节相同（格式未变，旧版本也能读回）。
//! 写出内容含随机标识的文件（AI 会话 / 执行日志）只做第 1 项，并校验行首 schema 与文件版本。
//!
//! 重新生成（只应在格式有意变化时做）：设置 `ZW_PERSIST_COMPAT_OUT`（输出目录）后运行
//! `zig build test -Dtest-filter="persist compat"`。
const std = @import("std");
const config = @import("../config.zig");
const store = @import("../store.zig");
const ui_state = @import("../ui_state.zig");
const background_progress = @import("../background_progress.zig");
const Playlist = @import("../background_playlist.zig").Playlist;
const imported_theme = @import("../imported_theme.zig");
const test_mode_credentials = @import("../test_mode_credentials.zig");
const host_key_store = @import("../../proto/ssh/host_key_store.zig");
const session_archive = @import("../../vt/session_archive.zig");
const recording_manifest = @import("../../vt/recording_manifest.zig");
const raw_stream_tap = @import("../../vt/raw_stream_tap.zig");
const timeline_mod = @import("../../vt/timeline.zig");
const attached = @import("../../ai/attached_service.zig");
const lifecycle_journal = @import("../../ai/lifecycle_journal.zig");
const session_journal = @import("../../ai/session_journal.zig");
const lifecycle_runtime = @import("../../ai/lifecycle_runtime.zig");
const identity = @import("../../host/identity.zig");

const a = std.testing.allocator;
const io = std.testing.io;

const fixture_dir = "../test_fixtures/persist_compat/";
/// 写出内容确定的文件：读旧 + 逐字节写新。
const Fixed = struct { name: []const u8, bytes: []const u8 };
const fixed = [_]Fixed{
    .{ .name = "config.toml", .bytes = @embedFile(fixture_dir ++ "config.toml") },
    .{ .name = "hosts.toml", .bytes = @embedFile(fixture_dir ++ "hosts.toml") },
    .{ .name = "ui-state.json", .bytes = @embedFile(fixture_dir ++ "ui-state.json") },
    .{ .name = "background-rotation.json", .bytes = @embedFile(fixture_dir ++ "background-rotation.json") },
    .{ .name = "themes/custom.itermcolors", .bytes = @embedFile(fixture_dir ++ "themes/custom.itermcolors") },
    .{ .name = "test-mode-credentials", .bytes = @embedFile(fixture_dir ++ "test-mode-credentials") },
    .{ .name = "known_hosts", .bytes = @embedFile(fixture_dir ++ "known_hosts") },
    .{ .name = "logs/history/index.tsv", .bytes = @embedFile(fixture_dir ++ "logs/history/index.tsv") },
    .{ .name = "logs/history/a.session.json", .bytes = @embedFile(fixture_dir ++ "logs/history/a.session.json") },
    .{ .name = "logs/raw.checkpoint", .bytes = @embedFile(fixture_dir ++ "logs/raw.checkpoint") },
    .{ .name = "logs/transcript.log", .bytes = @embedFile(fixture_dir ++ "logs/transcript.log") },
    .{ .name = "logs/transcript.cast", .bytes = @embedFile(fixture_dir ++ "logs/transcript.cast") },
};
const sessions_fixture = @embedFile(fixture_dir ++ "ai-sessions.v4.jsonl");
const lifecycle_fixture = @embedFile(fixture_dir ++ "ai/lifecycle.v4.json");

const known_host_line = "[node.example]:2222 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8g\n";
const credential_reference = "zw1_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
const transcript_payload = "服务器日志\r\nspace  preserved\r\n";
const sessions_question = "persist compat question";
const sessions_answer = "persist compat answer";

fn sampleConfig() config.Config {
    var value: config.Config = .{};
    value.ui.font_size = 15;
    value.ui.font_family = "JetBrains Mono";
    value.ai.permission_mode = .auto;
    value.ssh.reconnect_backoff = .{ 2, 3, 5, 8, 13 };
    value.ssh.reconnect_max = 4;
    value.transfer.max_tasks = 2;
    return value;
}
const hosts_source = "[[hosts]]\nname=\"node\"\nhost=\"10.0.0.8\"\nuser=\"ops\"\nstartup_commands=[\"uptime\"]\n\n[[hosts]]\nname=\"跳板\"\nhost=\"jump.example\"\nport=2222\nuser=\"root\"\n";
const sample_ui_state: ui_state.State = .{ .main_sidebar_collapsed = true, .narrow_sidebar_hint_shown = true };
const background_directory = "/Users/example/Pictures/背景";
const background_paths = [_][]const u8{ "/Users/example/Pictures/背景/a.png", "/Users/example/Pictures/背景/b.jpg", "/Users/example/Pictures/背景/c.heic" };
const archive_entry: session_archive.Entry = .{ .id = 7, .started_ms = 1_700_000_000_000, .ended_ms = 1_700_000_060_000, .duration_ms = 60_000, .exit_code = 0, .host = "node", .user = "ops", .cast_path = "logs/history/a.cast", .source_kind = .ssh, .saved_connection_id = 42 };
const manifest_generations = [_]recording_manifest.Generation{.{ .session_id = 9, .session_generation = 1, .initial_cols = 120, .initial_rows = 40, .receive_time_origin = 1_700_000_000_000 }};
const sample_manifest: recording_manifest.Manifest = .{ .archive_key = "0123456789abcdef0123456789abcdef", .recording_id = "fedcba9876543210fedcba9876543210", .source_kind = .ssh, .connection_id = 42, .started_ms = 1_700_000_000_000, .recording = .{ .generations = &manifest_generations } };

fn themeSource() ![]u8 {
    var xml: std.ArrayList(u8) = .empty;
    errdefer xml.deinit(a);
    const names = [_][]const u8{ "Ansi 0 Color", "Ansi 1 Color", "Ansi 2 Color", "Ansi 3 Color", "Ansi 4 Color", "Ansi 5 Color", "Ansi 6 Color", "Ansi 7 Color", "Ansi 8 Color", "Ansi 9 Color", "Ansi 10 Color", "Ansi 11 Color", "Ansi 12 Color", "Ansi 13 Color", "Ansi 14 Color", "Ansi 15 Color", "Background Color", "Foreground Color", "Cursor Color" };
    for (names, 0..) |name, index| try xml.print(a, "<key>{s}</key><dict><key>Red Component</key><real>{d}</real><key>Green Component</key><real>0.5</real><key>Blue Component</key><real>0</real></dict>", .{ name, @as(f64, @floatFromInt(index % 2)) });
    return xml.toOwnedSlice(a);
}

fn absolute(dir: std.Io.Dir, name: []const u8) ![]u8 {
    const root = try dir.realPathFileAlloc(io, ".", a);
    defer a.free(root);
    return std.fs.path.join(a, &.{ root, name });
}

/// 用当前代码、固定输入写出全部文件。旧代码写出的就是夹具。
fn produce(dir: std.Io.Dir) !void {
    try store.save(io, dir, "config.toml", sampleConfig());
    {
        var registry = try config.hosts.Registry.parse(a, hosts_source);
        defer registry.deinit();
        try store.saveHosts(io, dir, "hosts.toml", registry);
    }
    {
        const path = try absolute(dir, "ui-state.json");
        defer a.free(path);
        try ui_state.save(a, io, path, sample_ui_state);
    }
    {
        var list: Playlist = .{ .index = 1 };
        defer {
            for (list.paths.items) |item| a.free(item);
            list.paths.deinit(a);
        }
        for (background_paths) |item| try list.paths.append(a, try a.dupe(u8, item));
        try background_progress.save(io, dir, a, background_directory, &list);
    }
    {
        const source = try themeSource();
        defer a.free(source);
        try imported_theme.save(io, dir, "themes/custom.itermcolors", source);
    }
    {
        const root = try dir.realPathFileAlloc(io, ".", a);
        defer a.free(root);
        const backend = try test_mode_credentials.FileBackend.init(io, a, root);
        defer {
            backend.memory.deinit();
            std.heap.page_allocator.free(backend.path);
            a.destroy(backend);
        }
        const b = backend.backend();
        try b.add(b.context, "svc", credential_reference, "sk-compat-secret");
    }
    {
        var known = try host_key_store.HostKeyStore.parse(a, known_host_line);
        defer known.deinit();
        try known.save(io, dir, "known_hosts");
    }
    {
        var archive = session_archive.Archive{ .allocator = a, .io = io, .dir = dir };
        try archive.append(archive_entry);
    }
    try recording_manifest.save(a, io, dir, "logs/history/a.session.json", sample_manifest);
    {
        var tap = try raw_stream_tap.Tap.init(a, 64);
        defer tap.deinit();
        tap.append("abcdef");
        tap.markCheckpoint(1_700_000_000_123);
        try tap.saveCheckpoint(io, dir, "logs/raw.checkpoint");
    }
    {
        var timeline = try timeline_mod.Timeline.init(a, 16, 4096);
        defer timeline.deinit();
        try timeline.append(1_700_000_000_000, 0, transcript_payload);
        try timeline.append(1_700_000_000_250, transcript_payload.len, "done\r\n");
        try timeline.save(io, dir, "logs/transcript.log");
        try timeline.saveCast(io, dir, "logs/transcript.cast", 100, 30);
    }
}

/// AI 会话与执行日志：含随机标识，单独写出；只做读旧。
fn produceAi(dir: std.Io.Dir, data_root: []const u8) !void {
    {
        var host = attached.Host.init(a);
        defer host.deinit() catch unreachable;
        try host.ensurePersistence(data_root);
        const agent = try host.service.store.attach(.{ .tab = 42 });
        const ticket = try host.service.store.create(agent.id);
        try host.service.store.checkpoint(ticket, 1, &.{ .{ .content = sessions_question }, .{ .role = .assistant, .content = sessions_answer } }, true);
    }
    var journal = try lifecycle_journal.Journal.openMigrating(a, io, dir, lifecycle_runtime.file_name, lifecycle_runtime.legacy_file_name);
    defer journal.deinit();
    const request: lifecycle_journal.Request = .{ .context = .{ .conversation_id = identity.ConversationId.generate(), .task_id = identity.TaskId.generate(), .binding = .{ .tab = 42 }, .content = .{ .session = 7 }, .binding_revision = 1, .grant_revision = 1 }, .tool_id = "host.create_group", .request_key = "persist-compat-1", .canonical_hash = @splat(4), .turn_id = 1, .call_id = "persist-compat-call-1" };
    const handle = try journal.begin(request);
    try journal.update(handle, 1, .{ .stage = .committed, .created_group = 3, .committed_binding = .{ .tab = 43 }, .committed_binding_revision = 2, .notice_revision = 2 });
}

fn install(dir: std.Io.Dir, name: []const u8, bytes: []const u8) !void {
    if (std.fs.path.dirname(name)) |parent| try dir.createDirPath(io, parent);
    try dir.writeFile(io, .{ .sub_path = name, .data = bytes });
}

test "persist compat: files written before the shared persistence module read back with the same content" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    for (fixed) |file| try install(tmp.dir, file.name, file.bytes);
    {
        var loaded = try store.load(io, tmp.dir, a, "config.toml");
        defer loaded.deinit(a);
        const expected = sampleConfig();
        try std.testing.expectEqual(expected.ui.font_size, loaded.value.ui.font_size);
        try std.testing.expectEqualStrings(expected.ui.font_family, loaded.value.ui.font_family);
        try std.testing.expectEqual(expected.ai.permission_mode, loaded.value.ai.permission_mode);
        try std.testing.expectEqual(expected.ssh.reconnect_backoff, loaded.value.ssh.reconnect_backoff);
        try std.testing.expectEqual(expected.ssh.reconnect_max, loaded.value.ssh.reconnect_max);
        try std.testing.expectEqual(expected.transfer.max_tasks, loaded.value.transfer.max_tasks);
    }
    {
        var loaded = try store.loadHosts(io, tmp.dir, a, "hosts.toml");
        defer loaded.deinit();
        try std.testing.expectEqual(@as(usize, 2), loaded.hosts.len);
        try std.testing.expectEqualStrings("node", loaded.hosts[0].name);
        try std.testing.expectEqualStrings("uptime", loaded.hosts[0].startup_commands[0]);
        try std.testing.expectEqualStrings("跳板", loaded.hosts[1].name);
        try std.testing.expectEqual(@as(u16, 2222), loaded.hosts[1].port);
    }
    {
        const path = try absolute(tmp.dir, "ui-state.json");
        defer a.free(path);
        try std.testing.expectEqualDeep(sample_ui_state, ui_state.load(a, io, path));
    }
    {
        var list: Playlist = .{};
        defer {
            for (list.paths.items) |item| a.free(item);
            list.paths.deinit(a);
        }
        for (background_paths) |item| try list.paths.append(a, try a.dupe(u8, item));
        try background_progress.restore(io, tmp.dir, a, background_directory, &list);
        try std.testing.expectEqual(@as(usize, 1), list.index);
    }
    {
        var theme = try imported_theme.load(io, tmp.dir, a, "themes/custom.itermcolors");
        defer theme.deinit(a);
        const source = try themeSource();
        defer a.free(source);
        var expected = try imported_theme.parse(a, source, "custom.itermcolors");
        defer expected.deinit(a);
        try std.testing.expectEqualSlices(u32, &expected.ansi, &theme.ansi);
        try std.testing.expectEqual(expected.bg, theme.bg);
    }
    {
        const root = try tmp.dir.realPathFileAlloc(io, ".", a);
        defer a.free(root);
        const backend = try test_mode_credentials.FileBackend.init(io, a, root);
        defer {
            backend.memory.deinit();
            std.heap.page_allocator.free(backend.path);
            a.destroy(backend);
        }
        const b = backend.backend();
        const value = try b.get(b.context, a, "svc", credential_reference);
        defer a.free(value);
        try std.testing.expectEqualStrings("sk-compat-secret", value);
    }
    {
        var known = try host_key_store.HostKeyStore.load(io, tmp.dir, a, "known_hosts");
        defer known.deinit();
        try std.testing.expectEqualStrings(known_host_line, known.bytes());
    }
    {
        var archive = session_archive.Archive{ .allocator = a, .io = io, .dir = tmp.dir };
        var loaded = try archive.load(a);
        defer archive.freeEntries(&loaded);
        try std.testing.expectEqual(@as(usize, 1), loaded.items.len);
        try std.testing.expectEqualDeep(archive_entry, loaded.items[0]);
    }
    {
        const parsed = try recording_manifest.load(a, io, tmp.dir, "logs/history/a.session.json");
        defer parsed.deinit();
        try std.testing.expectEqualStrings(sample_manifest.archive_key, parsed.value.archive_key);
        try std.testing.expectEqual(@as(?u64, 42), parsed.value.connection_id);
        try std.testing.expectEqual(@as(u64, 9), parsed.value.recording.generations[0].session_id);
    }
    {
        const checkpoint = try raw_stream_tap.Tap.loadCheckpoint(io, tmp.dir, a, "logs/raw.checkpoint");
        try std.testing.expectEqual(@as(u64, 6), checkpoint.sequence);
        try std.testing.expectEqual(@as(i64, 1_700_000_000_123), checkpoint.timestamp_ms);
    }
    try std.testing.expect(std.mem.indexOf(u8, fixed[10].bytes, "space  preserved") != null);
    try std.testing.expect(std.mem.startsWith(u8, fixed[11].bytes, "{\"version\": 2") or std.mem.startsWith(u8, fixed[11].bytes, "{\"version\":2"));
}

test "persist compat: current writers produce byte-identical files for the same input" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try produce(tmp.dir);
    for (fixed) |file| {
        const bytes = try tmp.dir.readFileAlloc(io, file.name, a, .limited(1024 * 1024));
        defer a.free(bytes);
        std.testing.expectEqualStrings(file.bytes, bytes) catch |err| {
            std.debug.print("persist compat: {s} differs from the pre-refactor fixture\n", .{file.name});
            return err;
        };
        // 私有文件仍是 0600（导出与主题按原样沿用进程默认权限）。
        if (!std.mem.eql(u8, file.name, "themes/custom.itermcolors")) {
            const stat = try tmp.dir.statFile(io, file.name, .{});
            try std.testing.expectEqual(@as(u32, 0o600), @backingInt(stat.permissions) & 0o777);
        }
    }
}

test "persist compat: AI session and execution journals written before the shared module replay" {
    try std.testing.expect(std.mem.startsWith(u8, lifecycle_fixture, "{\"schema_version\":3,"));
    var lines = std.mem.splitScalar(u8, sessions_fixture, '\n');
    var rows: usize = 0;
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        try std.testing.expect(std.mem.startsWith(u8, line, "{\"schema\":4,"));
        rows += 1;
    }
    try std.testing.expect(rows != 0);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try install(tmp.dir, session_journal.file_name, sessions_fixture);
    try install(tmp.dir, lifecycle_runtime.file_name, lifecycle_fixture);
    const path = try std.fmt.allocPrint(a, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer a.free(path);
    {
        var host = attached.Host.init(a);
        defer host.deinit() catch unreachable;
        try host.ensurePersistence(path);
        try std.testing.expect(host.persistence_failure == null);
        try std.testing.expectEqual(@as(usize, 1), host.service.store.records.items.len);
        const record = host.service.store.records.items[0];
        const messages = record.history.messages;
        try std.testing.expectEqual(@as(usize, 2), messages.len);
        try std.testing.expectEqualStrings(sessions_question, messages[0].content);
        try std.testing.expectEqualStrings(sessions_answer, messages[1].content);
    }
    // 回放不改写日志（没有残行、没有迁移）。
    const after = try tmp.dir.readFileAlloc(io, session_journal.file_name, a, .unlimited);
    defer a.free(after);
    try std.testing.expectEqualStrings(sessions_fixture, after);
    var journal = try lifecycle_journal.Journal.openMigrating(a, io, tmp.dir, lifecycle_runtime.file_name, lifecycle_runtime.legacy_file_name);
    defer journal.deinit();
    try std.testing.expectEqual(@as(usize, 1), journal.records.items.len);
    try std.testing.expectEqualStrings("persist-compat-1", journal.records.items[0].request_key);
    try std.testing.expectEqual(lifecycle_journal.Stage.committed, journal.records.items[0].stage);
    const lifecycle_after = try tmp.dir.readFileAlloc(io, lifecycle_runtime.file_name, a, .unlimited);
    defer a.free(lifecycle_after);
    try std.testing.expectEqualStrings(lifecycle_fixture, lifecycle_after);
}

test "persist compat: regenerate fixtures (ZW_PERSIST_COMPAT_OUT)" {
    const out = if (std.c.getenv("ZW_PERSIST_COMPAT_OUT")) |value| std.mem.span(value) else return error.SkipZigTest;
    var dir = try std.Io.Dir.cwd().createDirPathOpen(io, out, .{});
    defer dir.close(io);
    try produce(dir);
    try produceAi(dir, out);
}

test "persist durability: config, hosts and AI journal replacements fsync their directory, one extra fsync per save" {
    const persist = @import("../../shared/base/persist.zig");
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    persist.testing.reset();
    try store.save(io, tmp.dir, "config.toml", sampleConfig());
    // Per save: the data fsync it always had, plus exactly one directory fsync.
    try std.testing.expectEqual(@as(usize, 1), persist.testing.data_syncs);
    try std.testing.expectEqual(@as(usize, 1), persist.testing.dir_syncs);
    {
        var registry = try config.hosts.Registry.parse(a, hosts_source);
        defer registry.deinit();
        try store.saveHosts(io, tmp.dir, "hosts.toml", registry);
    }
    try std.testing.expectEqual(@as(usize, 2), persist.testing.data_syncs);
    try std.testing.expectEqual(@as(usize, 2), persist.testing.dir_syncs);

    // AI session journal: a torn tail is repaired by a whole-file replacement on open.
    const torn = try std.mem.concat(a, u8, &.{ sessions_fixture, "{\"schema\":4,\"torn" });
    defer a.free(torn);
    try install(tmp.dir, session_journal.file_name, torn);
    const path = try std.fmt.allocPrint(a, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer a.free(path);
    persist.testing.reset();
    {
        var host = attached.Host.init(a);
        defer host.deinit() catch unreachable;
        try host.ensurePersistence(path);
        try std.testing.expect(host.persistence_failure == null);
    }
    const repaired = try tmp.dir.readFileAlloc(io, session_journal.file_name, a, .unlimited);
    defer a.free(repaired);
    try std.testing.expectEqualStrings(sessions_fixture, repaired);
    try std.testing.expect(persist.testing.data_syncs >= 1);
    try std.testing.expectEqual(persist.testing.data_syncs, persist.testing.dir_syncs);

    // AI execution (lifecycle) journal: every rewrite is followed by its directory fsync.
    persist.testing.reset();
    var journal = try lifecycle_journal.Journal.openMigrating(a, io, tmp.dir, "ai/durability-lifecycle.json", "ai/durability-lifecycle.legacy.json");
    defer journal.deinit();
    const request: lifecycle_journal.Request = .{ .context = .{ .conversation_id = identity.ConversationId.generate(), .task_id = identity.TaskId.generate(), .binding = .{ .tab = 42 }, .content = .{ .session = 7 }, .binding_revision = 1, .grant_revision = 1 }, .tool_id = "host.create_group", .request_key = "durability-1", .canonical_hash = @splat(4), .turn_id = 1, .call_id = "durability-call-1" };
    const handle = try journal.begin(request);
    try journal.update(handle, 1, .{ .stage = .committed, .created_group = 3, .committed_binding = .{ .tab = 43 }, .committed_binding_revision = 2, .notice_revision = 2 });
    try std.testing.expect(persist.testing.data_syncs >= 2);
    try std.testing.expectEqual(persist.testing.data_syncs, persist.testing.dir_syncs);
}
