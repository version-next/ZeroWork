//! test-mode 构建的凭据后端：私有数据目录里的一个 0600 文件，**永不调用 macOS Security / 钥匙串**。
//!
//! 背景：test-mode 应用在隔离的 HOME / 数据目录里运行（e2e、自动化）。配置里有明文 `ai.providers.api_key`
//! 时，加载路径会把它迁移成 `api_key_ref` 并写进凭据存储；原先这一步走原生钥匙串（含授权提示），
//! 在无界面的自动化进程里会一直等待，应用启动即挂起且没有任何输出，同时也会碰真实的钥匙串。
//! test-mode 改用这里的文件后端：只在本次实例的数据目录里读写，随数据目录一起删除。
//! 正式构建不链接调用路径（只在 `application_test_mode` 为真时由组合根选用）。
const std = @import("std");
const persist_io = @import("../shared/base/persist.zig");
const credentials = @import("credential_store.zig");

pub const file_name = "test-mode-credentials";

pub const FileBackend = struct {
    io: std.Io,
    /// 数据目录下的文件绝对路径（由 init 分配）。
    path: []u8,
    memory: credentials.MemoryBackend = .{},

    /// 读取已有的文件（不存在时为空）。数据目录由调用方保证是本实例私有的 0700 目录。
    pub fn init(io: std.Io, allocator: std.mem.Allocator, directory: []const u8) !*FileBackend {
        const self = try allocator.create(FileBackend);
        errdefer allocator.destroy(self);
        self.* = .{ .io = io, .path = try std.fs.path.join(std.heap.page_allocator, &.{ directory, file_name }) };
        errdefer std.heap.page_allocator.free(self.path);
        try self.load();
        return self;
    }
    pub fn backend(self: *FileBackend) credentials.Backend {
        return .{ .context = self, .get = read, .add = write, .remove = erase, .collect = collect };
    }

    fn load(self: *FileBackend) !void {
        const source = std.Io.Dir.cwd().readFileAlloc(self.io, self.path, std.heap.page_allocator, .limited(4 * 1024 * 1024)) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        };
        defer {
            std.crypto.secureZero(u8, source);
            std.heap.page_allocator.free(source);
        }
        var lines = persist_io.lines(source);
        while (lines.next()) |line| {
            const tab = std.mem.indexOfScalar(u8, line, '\t') orelse return error.InvalidTestCredentialFile;
            const key = line[0..tab];
            const hex = line[tab + 1 ..];
            if (hex.len % 2 != 0) return error.InvalidTestCredentialFile;
            const value = try std.heap.page_allocator.alloc(u8, hex.len / 2);
            errdefer std.heap.page_allocator.free(value);
            _ = std.fmt.hexToBytes(value, hex) catch return error.InvalidTestCredentialFile;
            const owned_key = try std.heap.page_allocator.dupe(u8, key);
            errdefer std.heap.page_allocator.free(owned_key);
            try self.memory.values.put(std.heap.page_allocator, owned_key, value);
        }
    }
    fn persist(self: *FileBackend) !void {
        var bytes: std.ArrayList(u8) = .empty;
        defer {
            std.crypto.secureZero(u8, bytes.items);
            bytes.deinit(std.heap.page_allocator);
        }
        var it = self.memory.values.iterator();
        while (it.next()) |entry| {
            try bytes.appendSlice(std.heap.page_allocator, entry.key_ptr.*);
            try bytes.append(std.heap.page_allocator, '\t');
            for (entry.value_ptr.*) |byte| try bytes.print(std.heap.page_allocator, "{x:0>2}", .{byte});
            try bytes.append(std.heap.page_allocator, '\n');
        }
        try persist_io.writeAtomic(self.io, std.Io.Dir.cwd(), self.path, bytes.items, .{});
    }

    fn cast(context: *anyopaque) *FileBackend {
        return @ptrCast(@alignCast(context));
    }
    fn read(context: *anyopaque, a: std.mem.Allocator, s: []const u8, r: []const u8) anyerror![]u8 {
        const self = cast(context);
        return self.memory.backend().get(&self.memory, a, s, r);
    }
    fn write(context: *anyopaque, s: []const u8, r: []const u8, value: []const u8) anyerror!void {
        const self = cast(context);
        try self.memory.backend().add(&self.memory, s, r, value);
        try self.persist();
    }
    fn erase(context: *anyopaque, s: []const u8, r: []const u8) anyerror!void {
        const self = cast(context);
        try self.memory.backend().remove(&self.memory, s, r);
        try self.persist();
    }
    fn collect(context: *anyopaque, s: []const u8, keep: []const []const u8) anyerror!void {
        const self = cast(context);
        try self.memory.backend().collect(&self.memory, s, keep);
        try self.persist();
    }
};

test "test-mode credential file persists across instances with 0600 and never touches Security" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(std.testing.io, &buffer);
    const directory = buffer[0..length];
    const hex: [64]u8 = @splat('a');
    const reference = "zw1_" ++ hex;
    {
        const first = try FileBackend.init(std.testing.io, std.testing.allocator, directory);
        defer {
            first.memory.deinit();
            std.heap.page_allocator.free(first.path);
            std.testing.allocator.destroy(first);
        }
        const b = first.backend();
        try b.add(b.context, "svc", reference, "sk-plain-secret");
    }
    const stat = try tmp.dir.statFile(std.testing.io, file_name, .{});
    try std.testing.expectEqual(@as(u32, 0o600), @backingInt(stat.permissions) & 0o777);
    const second = try FileBackend.init(std.testing.io, std.testing.allocator, directory);
    defer {
        second.memory.deinit();
        std.heap.page_allocator.free(second.path);
        std.testing.allocator.destroy(second);
    }
    const b = second.backend();
    const value = try b.get(b.context, std.testing.allocator, "svc", reference);
    defer std.testing.allocator.free(value);
    try std.testing.expectEqualStrings("sk-plain-secret", value);
    try b.collect(b.context, "svc", &.{});
    try std.testing.expectError(error.CredentialMissing, b.get(b.context, std.testing.allocator, "svc", reference));
}
