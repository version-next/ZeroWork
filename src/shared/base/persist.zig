//! 应用自有文件的唯一共享持久化实现（persist-async，一致性审查 #10）。
//!
//! 所有"写一个完整文件"的地方都走这里：临时文件 → 写入 → （按需）fsync → rename/link →
//! （按需）目录 fsync。文件锁、私有权限、schema 版本检查、"读旧写新"迁移与日志残行处理也只在这里实现。
//!
//! 各类文件的约定（改造前的行为，原样保留）：
//!
//! | 文件 | 落盘 | 损坏时 |
//! |---|---|---|
//! | config.toml / hosts.toml / known_hosts | durable，`.lock` 串行写入 | 拒绝加载，原文件不动 |
//! | ui-state.json / 会话组布局 / 背景轮播进度 | durable | 视同不存在（用默认值） |
//! | ai-sessions.v4.jsonl | 追加 + fsync；整份替换 durable；`.lock` | 末尾残行丢弃，其余坏行整份失败 |
//! | ai/lifecycle.v4.json / BMC 管理日志 | durable（BMC 另做目录 fsync）；AI 有 `.lock` | 整份失败 |
//! | 会话记录索引 index.tsv | durable | 跳过坏行 |
//! | 录制清单 / 本地录制检查点 / 原始流检查点 / transcript / cast | durable | 拒绝（版本不符报错） |
//! | 导入主题 / 终端与会话导出 | flush_only（不 fsync） | — |
//!
//! 不在这里的：进程级数据目录锁（platform/data_scope_lock.c，含符号链接与属主检查）、
//! BMC TLS 证书固定（platform/bmc_tls_trust.c）、trusted edit 临时目录（local/trusted_edit_native.c）。
//! 它们是原生实现的安全边界，有各自更严格的约束，不收进这里。
const std = @import("std");
const builtin = @import("builtin");

/// 应用私有文件（0600）与目录（0700）。与 umask 无关。
pub const private_file_mode: u32 = 0o600;
pub const private_dir_mode: u32 = 0o700;
pub const private_file: std.Io.File.Permissions = @fromBackingInt(private_file_mode);
pub const private_dir: std.Io.Dir.Permissions = @fromBackingInt(private_dir_mode);

// ---------------------------------------------------------------------------
// 原子写
// ---------------------------------------------------------------------------

pub const Durability = enum {
    /// 发布（rename/link）之前对数据 fsync。应用数据一律用这个。
    durable,
    /// 只保证写完再整体替换，不 fsync。只用于导出类文件与可重建的缓存（需显式声明）。
    flush_only,
};

pub const Publish = enum {
    /// 覆盖同名文件（rename）。
    replace,
    /// 只在目标不存在时创建（link）；已存在返回 `error.PathAlreadyExists`。
    create_new,
};

pub const WriteOptions = struct {
    /// null = 进程默认权限（受 umask 影响）。只有非私有的用户文件（导入的主题）才用 null。
    permissions: ?std.Io.File.Permissions = private_file,
    make_path: bool = false,
    publish: Publish = .replace,
    durability: Durability = .durable,
    /// 发布后对目标所在目录 fsync（让 rename 本身也落盘）：`sub_path` 不含目录部分时是 `dir` 本身，
    /// 否则是 `dir` 下的父目录。每次保存多一次目录 fsync。
    sync_dir: bool = false,
};

/// 测试计数：单测据此断言某处确实 fsync 了（数据 / 目录）。只在测试构建里计数。
pub const testing = struct {
    pub threadlocal var data_syncs: usize = 0;
    pub threadlocal var dir_syncs: usize = 0;
    pub fn reset() void {
        data_syncs = 0;
        dir_syncs = 0;
    }
};

/// 分步写：`begin` → 用 `file()` / `writer()` 写 → （可选）`syncData` 后再做调用方检查 → `commit`。
/// `deinit` 总要调用；没有 `commit` 时临时文件被删除，目标文件不变。
pub const AtomicWriter = struct {
    io: std.Io,
    dir: std.Io.Dir,
    options: WriteOptions,
    atomic: std.Io.File.Atomic,
    /// Borrowed from the caller for the writer's lifetime (directory fsync after publishing).
    sub_path: []const u8,
    data_synced: bool = false,

    pub fn begin(io: std.Io, dir: std.Io.Dir, sub_path: []const u8, options: WriteOptions) !AtomicWriter {
        const atomic = try dir.createFileAtomic(io, sub_path, .{
            .permissions = options.permissions orelse .default_file,
            .make_path = options.make_path,
            .replace = options.publish == .replace,
        });
        return .{ .io = io, .dir = dir, .options = options, .atomic = atomic, .sub_path = sub_path };
    }

    pub fn deinit(self: *AtomicWriter) void {
        self.atomic.deinit(self.io);
    }

    pub fn file(self: *AtomicWriter) std.Io.File {
        return self.atomic.file;
    }

    pub fn writer(self: *AtomicWriter, buffer: []u8) std.Io.File.Writer {
        return self.atomic.file.writer(self.io, buffer);
    }

    /// 立即 fsync 数据（`durable` 时）。用于"先落盘、再做一次冲突检查、再发布"的调用方。
    pub fn syncData(self: *AtomicWriter) !void {
        if (self.options.durability != .durable or self.data_synced) return;
        try self.atomic.file.sync(self.io);
        if (builtin.is_test) testing.data_syncs += 1;
        self.data_synced = true;
    }

    /// 按选项 fsync、发布、（可选）目录 fsync。
    pub fn commit(self: *AtomicWriter) !void {
        try self.syncData();
        switch (self.options.publish) {
            .replace => try self.atomic.replace(self.io),
            .create_new => try self.atomic.link(self.io),
        }
        if (self.options.sync_dir) try syncParentDirectory(self.io, self.dir, self.sub_path);
    }
};

/// fsync the directory that holds `sub_path` (relative to `dir`, or absolute).
pub fn syncParentDirectory(io: std.Io, dir: std.Io.Dir, sub_path: []const u8) !void {
    const parent = std.fs.path.dirname(sub_path) orelse return syncDirectory(dir);
    var opened = dir.openDir(io, parent, .{}) catch return error.DirectorySyncFailed;
    defer opened.close(io);
    try syncDirectory(opened);
}

/// 一次性写入完整内容。
pub fn writeAtomic(io: std.Io, dir: std.Io.Dir, sub_path: []const u8, bytes: []const u8, options: WriteOptions) !void {
    var w = try AtomicWriter.begin(io, dir, sub_path, options);
    defer w.deinit();
    try w.file().writePositionalAll(io, bytes, 0);
    try w.commit();
}

/// 目录 fsync（rename/新建文件本身落盘）。被信号打断时重试；其他失败返回 `error.DirectorySyncFailed`。
pub fn syncDirectory(dir: std.Io.Dir) !void {
    while (true) switch (std.posix.errno(std.c.fsync(dir.handle))) {
        .SUCCESS => break,
        .INTR => continue,
        else => return error.DirectorySyncFailed,
    };
    if (builtin.is_test) testing.dir_syncs += 1;
}

// ---------------------------------------------------------------------------
// 文件锁
// ---------------------------------------------------------------------------

/// `<sub_path>.lock`：每个数据文件一把咨询锁，跨原子替换保持（锁的是旁边的锁文件，不是数据 inode）。
/// 独占、非阻塞（被占用时返回 `error.WouldBlock`），锁文件 0600，按需创建父目录。关闭返回的文件即释放。
pub fn acquireLock(io: std.Io, dir: std.Io.Dir, sub_path: []const u8) !std.Io.File {
    if (std.fs.path.dirname(sub_path)) |parent| try dir.createDirPath(io, parent);
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const lock_path = std.fmt.bufPrint(&buffer, "{s}.lock", .{sub_path}) catch return error.NameTooLong;
    return dir.createFile(io, lock_path, .{ .truncate = false, .lock = .exclusive, .lock_nonblocking = true, .permissions = private_file });
}

// ---------------------------------------------------------------------------
// schema 版本与"读旧写新"
// ---------------------------------------------------------------------------

/// 本版本能读的 schema 区间（含两端）。写出时总是用 `max`（或调用方按内容选择的不高于 `max` 的值）。
pub const SchemaRange = struct {
    min: u32,
    max: u32,

    pub fn exactly(version: u32) SchemaRange {
        return .{ .min = version, .max = version };
    }
    pub fn accepts(self: SchemaRange, version: anytype) bool {
        return version >= self.min and version <= self.max;
    }
};

/// "读旧写新"：新文件名还不存在时读取旧文件名的内容（只读：不加锁、不改写、不删除），由调用方
/// 校验后写进新文件。旧版本继续读它认识的旧文件，不会因为新格式的行而失败。
/// 返回 null：新旧同名，或旧文件也不存在。
pub fn readLegacy(allocator: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, path: []const u8, legacy: []const u8, limit: std.Io.Limit) !?[]u8 {
    if (std.mem.eql(u8, path, legacy)) return null;
    return dir.readFileAlloc(io, legacy, allocator, limit) catch |err| switch (err) {
        error.FileNotFound => null,
        else => err,
    };
}

// ---------------------------------------------------------------------------
// 按行的日志
// ---------------------------------------------------------------------------

/// 追加写入的日志在崩溃时可能留下没写完的末行。返回只含完整行（以 `\n` 结尾）的前缀长度；
/// 内容非空却连一个完整行都没有时返回 null（整份不可用）。
pub fn committedLength(source: []const u8) ?usize {
    if (source.len == 0 or source[source.len - 1] == '\n') return source.len;
    if (std.mem.lastIndexOfScalar(u8, source, '\n')) |index| return index + 1;
    return null;
}

/// 逐行遍历（跳过空行）。坏行怎么处理由调用方决定：跳过（`continue`）或整份失败（返回错误）。
pub const Lines = struct {
    inner: std.mem.SplitIterator(u8, .scalar),

    pub fn next(self: *Lines) ?[]const u8 {
        while (self.inner.next()) |line| if (line.len != 0) return line;
        return null;
    }
};
pub fn lines(bytes: []const u8) Lines {
    return .{ .inner = std.mem.splitScalar(u8, bytes, '\n') };
}

// ---------------------------------------------------------------------------
// 测试
// ---------------------------------------------------------------------------

test "persist atomic write replaces privately and leaves no temporary file" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    testing.reset();
    try writeAtomic(io, tmp.dir, "nested/a.json", "first-longer-content", .{ .make_path = true });
    try writeAtomic(io, tmp.dir, "nested/a.json", "second", .{ .make_path = true });
    const bytes = try tmp.dir.readFileAlloc(io, "nested/a.json", std.testing.allocator, .limited(64));
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("second", bytes);
    const stat = try tmp.dir.statFile(io, "nested/a.json", .{});
    try std.testing.expectEqual(private_file_mode, @backingInt(stat.permissions) & 0o777);
    try std.testing.expectEqual(@as(usize, 2), testing.data_syncs);
    try std.testing.expectEqual(@as(usize, 0), testing.dir_syncs);
    var nested = try tmp.dir.openDir(io, "nested", .{ .iterate = true });
    defer nested.close(io);
    var it = nested.iterate();
    var count: usize = 0;
    while (try it.next(io)) |_| count += 1;
    try std.testing.expectEqual(@as(usize, 1), count);
}

test "persist atomic write durability, directory sync and create-new are explicit" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    testing.reset();
    try writeAtomic(io, tmp.dir, "export.txt", "x", .{ .durability = .flush_only });
    try std.testing.expectEqual(@as(usize, 0), testing.data_syncs);
    try writeAtomic(io, tmp.dir, "journal.json", "y", .{ .sync_dir = true });
    try std.testing.expectEqual(@as(usize, 1), testing.data_syncs);
    try std.testing.expectEqual(@as(usize, 1), testing.dir_syncs);
    try writeAtomic(io, tmp.dir, "backup", "z", .{ .publish = .create_new });
    try std.testing.expectError(error.PathAlreadyExists, writeAtomic(io, tmp.dir, "backup", "other", .{ .publish = .create_new }));
    const bytes = try tmp.dir.readFileAlloc(io, "backup", std.testing.allocator, .limited(8));
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("z", bytes);
}

test "persist directory sync covers the parent of a nested path: one extra fsync per save" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    testing.reset();
    try writeAtomic(io, tmp.dir, "nested/deeper/config.toml", "a", .{ .make_path = true, .sync_dir = true });
    try writeAtomic(io, tmp.dir, "nested/deeper/config.toml", "b", .{ .make_path = true, .sync_dir = true });
    // Per save: one data fsync (as before) + one directory fsync (new).
    try std.testing.expectEqual(@as(usize, 2), testing.data_syncs);
    try std.testing.expectEqual(@as(usize, 2), testing.dir_syncs);
    const bytes = try tmp.dir.readFileAlloc(io, "nested/deeper/config.toml", std.testing.allocator, .limited(8));
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("b", bytes);
}

test "persist uncommitted writer leaves the previous file untouched" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try writeAtomic(io, tmp.dir, "a", "old", .{});
    {
        var w = try AtomicWriter.begin(io, tmp.dir, "a", .{});
        defer w.deinit();
        try w.file().writePositionalAll(io, "new", 0);
        try w.syncData();
    }
    const bytes = try tmp.dir.readFileAlloc(io, "a", std.testing.allocator, .limited(8));
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("old", bytes);
}

test "persist lock is exclusive, private and released on close" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const first = try acquireLock(io, tmp.dir, "ai/data.json");
    try std.testing.expectError(error.WouldBlock, acquireLock(io, tmp.dir, "ai/data.json"));
    const stat = try tmp.dir.statFile(io, "ai/data.json.lock", .{});
    try std.testing.expectEqual(private_file_mode, @backingInt(stat.permissions) & 0o777);
    first.close(io);
    const again = try acquireLock(io, tmp.dir, "ai/data.json");
    again.close(io);
}

test "persist legacy read and committed journal prefix" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const a = std.testing.allocator;
    try std.testing.expectEqual(@as(?[]u8, null), try readLegacy(a, io, tmp.dir, "new.jsonl", "old.jsonl", .unlimited));
    try tmp.dir.writeFile(io, .{ .sub_path = "old.jsonl", .data = "row\n" });
    try std.testing.expectEqual(@as(?[]u8, null), try readLegacy(a, io, tmp.dir, "old.jsonl", "old.jsonl", .unlimited));
    const legacy = (try readLegacy(a, io, tmp.dir, "new.jsonl", "old.jsonl", .unlimited)).?;
    defer a.free(legacy);
    try std.testing.expectEqualStrings("row\n", legacy);
    try std.testing.expectEqual(@as(?usize, 0), committedLength(""));
    try std.testing.expectEqual(@as(?usize, 4), committedLength("a\nb\n"));
    try std.testing.expectEqual(@as(?usize, 2), committedLength("a\nbro"));
    try std.testing.expectEqual(@as(?usize, null), committedLength("partial"));
    var it = lines("a\n\nb\n");
    try std.testing.expectEqualStrings("a", it.next().?);
    try std.testing.expectEqualStrings("b", it.next().?);
    try std.testing.expectEqual(@as(?[]const u8, null), it.next());
    const range: SchemaRange = .{ .min = 1, .max = 3 };
    try std.testing.expect(range.accepts(@as(u8, 1)) and range.accepts(@as(u32, 3)));
    try std.testing.expect(!range.accepts(@as(u32, 0)) and !range.accepts(@as(u32, 4)));
    try std.testing.expect(SchemaRange.exactly(1).accepts(@as(u32, 1)) and !SchemaRange.exactly(1).accepts(@as(u32, 2)));
}
