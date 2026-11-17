//! Isolated real /bin/zsh integration; no user startup files or window.
const std = @import("std");
const trusted = @import("../trusted_edit.zig");
const pty = @import("../pty.zig");
const native = @import("../native.zig");
const a = std.testing.allocator;
extern "c" fn setenv([*:0]const u8, [*:0]const u8, c_int) c_int;
extern "c" fn unsetenv([*:0]const u8) c_int;
extern "c" fn sigsuspend(*const u32) c_int;
fn pause() void {
    const delay: std.c.timespec = .{ .sec = 0, .nsec = 5 * std.time.ns_per_ms };
    _ = std.c.nanosleep(&delay, null);
}
const Fixture = struct {
    tmp: std.testing.TmpDir,
    path: [:0]u8,
    old: ?[:0]u8,
    bridge: trusted.Bridge,
    session: pty.Session,
    output: std.ArrayList(u8) = .empty,
    fn init() !Fixture {
        return initWithStartup("");
    }
    fn initWithStartup(startup: []const u8) !Fixture {
        var tmp = std.testing.tmpDir(.{});
        errdefer tmp.cleanup();
        try tmp.dir.writeFile(std.testing.io, .{ .sub_path = ".zshenv", .data = "PROMPT=''\nRPROMPT=''\n" });
        const zshrc = try std.mem.concat(a, u8, &.{ startup, "\nbindkey -e\nexport LC_ALL=en_US.UTF-8\n_zw_test_pending() { print -r -- $PENDING > \"$ZDOTDIR/pending\"; zle -U Q; print -r -- $KEYS_QUEUED_COUNT >> \"$ZDOTDIR/pending\"; _zw_edit_request replace 991 $_zw_token $_zw_revision \"$BUFFER\" $CURSOR invalid-replacement; }\nzle -N _zw_test_pending\nbindkey '^Xp' _zw_test_pending\n" });
        defer a.free(zshrc);
        try tmp.dir.writeFile(std.testing.io, .{ .sub_path = ".zshrc", .data = zshrc });
        const path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", a);
        errdefer a.free(path);
        const old = if (std.c.getenv("ZDOTDIR")) |v| try a.dupeSentinel(u8, std.mem.span(v), 0) else null;
        _ = setenv("ZDOTDIR", path.ptr, 1);
        errdefer {
            if (old) |v| {
                _ = setenv("ZDOTDIR", v.ptr, 1);
                a.free(v);
            } else _ = unsetenv("ZDOTDIR");
        }
        const owner: @import("../../host/identity.zig").SessionHandle = .{ .session_id = @fromBackingInt(591) };
        var bridge = try trusted.Bridge.init(a, owner);
        errdefer bridge.deinit();
        var failure: native.Failure = .{};
        const session = try pty.Session.start(a, owner, .{ .owner = .{ .session = owner }, .operation_id = 1, .attempt_id = 1 }, .{ .bootstrap = bridge.bootstrap() }, &failure);
        return .{ .tmp = tmp, .path = path, .old = old, .bridge = bridge, .session = session };
    }
    fn deinit(self: *Fixture) void {
        const until = native.zw_local_monotonic_ms() + 6500;
        while (self.session.cleanup != .released and native.zw_local_monotonic_ms() < until) {
            self.tick() catch {};
            _ = self.session.closeStep(self.session.owner) catch {};
            pause();
        }
        self.session.deinit() catch {};
        self.bridge.deinit();
        self.output.deinit(a);
        if (self.old) |v| {
            _ = setenv("ZDOTDIR", v.ptr, 1);
            a.free(v);
        } else _ = unsetenv("ZDOTDIR");
        a.free(self.path);
        self.tmp.cleanup();
    }
    fn tick(self: *Fixture) !void {
        self.bridge.poll(try self.session.pid(), @intCast(native.zw_local_monotonic_ms()));
        self.bridge.synchronizeInput();
        var bytes: [8192]u8 = undefined;
        for (0..16) |_| switch (try self.session.readOutput(self.session.owner, &bytes)) {
            .bytes => |n| try self.output.appendSlice(a, bytes[0..n]),
            else => break,
        };
    }
    fn write(self: *Fixture, text: []const u8) !void {
        var offset: usize = 0;
        const until = native.zw_local_monotonic_ms() + 2000;
        while (offset < text.len and native.zw_local_monotonic_ms() < until) switch (try self.session.write(self.session.owner, text[offset..])) {
            .bytes => |n| offset += n,
            .would_block => pause(),
        };
        try std.testing.expectEqual(text.len, offset);
    }
    fn waitBuffer(self: *Fixture, text: []const u8) !void {
        const until = native.zw_local_monotonic_ms() + 3000;
        while (native.zw_local_monotonic_ms() < until) {
            try self.tick();
            if (self.bridge.snapshot) |s| if (!self.bridge.input_dirty and std.mem.eql(u8, s.buffer, text) and s.editable()) return;
            pause();
        }
        std.debug.print("ZSH output: {s}\nhello={} disabled={}\n", .{ self.output.items, self.bridge.hello, self.bridge.disabled });
        return error.SnapshotTimeout;
    }
    fn request(self: *Fixture, operation: u64, kind: trusted.edit.Kind, replacement: []const u8) !trusted.edit.Outcome {
        const s = self.bridge.snapshot.?;
        try self.bridge.request(.{ .operation = operation, .token = s.token, .revision = s.revision, .kind = kind, .replacement = replacement, .lease = s.lease }, @intCast(native.zw_local_monotonic_ms()));
        const until = native.zw_local_monotonic_ms() + 2000;
        while (native.zw_local_monotonic_ms() < until) {
            try self.tick();
            if (self.bridge.outcome) |outcome| {
                self.bridge.outcome = null;
                return outcome;
            }
            pause();
        }
        return error.AckTimeout;
    }
};

test "slow real shell startup remains untrusted then authenticates, executes and releases" {
    var f = try Fixture.initWithStartup("/bin/sleep 3\n");
    var active = true;
    defer if (active) f.deinit();
    const directory = try a.dupe(u8, std.mem.span(f.bridge.bootstrap()));
    defer a.free(directory);
    const until = native.zw_local_monotonic_ms() + 2500;
    while (native.zw_local_monotonic_ms() < until) {
        try f.tick();
        try std.testing.expect(!f.bridge.hello and !f.bridge.disabled and f.bridge.snapshot == null);
        try std.testing.expectError(error.TrustedEditUnavailable, f.bridge.request(.{ .operation = 1, .kind = .begin, .token = 1, .revision = 0 }, @intCast(native.zw_local_monotonic_ms())));
        pause();
    }
    try f.waitBuffer("");
    try std.testing.expect((try f.request(1, .begin, "")).applied);
    try std.testing.expect((try f.request(2, .end, "")).applied);
    // A real command enters ZLE through the same trusted replacement primitive
    // as command completion; it executes only after explicit terminal Enter.
    const command = try std.fmt.allocPrint(a, "printf delayed-ok > '{s}/delayed-marker'", .{f.path});
    defer a.free(command);
    try std.testing.expect((try f.request(3, .replace, command)).applied);
    try std.testing.expectError(error.FileNotFound, f.tmp.dir.openFile(std.testing.io, "delayed-marker", .{}));
    try f.write("\r");
    try f.waitBuffer("");
    const marker = try f.tmp.dir.openFile(std.testing.io, "delayed-marker", .{});
    marker.close(std.testing.io);
    try f.write("exit\r");
    const exit_until = native.zw_local_monotonic_ms() + 3000;
    var exited = false;
    while (native.zw_local_monotonic_ms() < exit_until) {
        try f.tick();
        if (try f.session.pollExit()) |_| {
            exited = true;
            break;
        }
        pause();
    }
    try std.testing.expect(exited);
    try std.testing.expect(!f.bridge.hello and f.bridge.snapshot == null);
    try std.testing.expectEqual(native.Cleanup.released, try f.session.closeStep(f.session.owner));
    f.deinit();
    active = false;
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.openDirAbsolute(std.testing.io, directory, .{}));
}

test "unrelated same-user socket peer cannot authenticate during delayed shell startup" {
    var f = try Fixture.initWithStartup("/bin/sleep 3\n");
    defer f.deinit();
    const fd = std.c.socket(std.c.AF.UNIX, std.c.SOCK.STREAM, 0);
    try std.testing.expect(fd >= 0);
    defer _ = std.c.close(fd);
    var address: std.c.sockaddr.un = .{ .path = @splat(0) };
    const path = try std.fmt.bufPrint(&address.path, "{s}/control", .{std.mem.span(f.bridge.bootstrap())});
    try std.testing.expect(path.len < address.path.len);
    try std.testing.expectEqual(@as(c_int, 0), std.c.connect(fd, @ptrCast(&address), @sizeOf(@TypeOf(address))));
    try f.tick();
    try std.testing.expect(!f.bridge.hello and !f.bridge.disabled and f.bridge.snapshot == null and f.bridge.connected_at == 0);
    // Rejection must leave the real owning shell able to connect later.
    const until = native.zw_local_monotonic_ms() + 5000;
    while (native.zw_local_monotonic_ms() < until) {
        try f.tick();
        if (f.bridge.hello and f.bridge.snapshot != null and !f.bridge.input_dirty) return;
        pause();
    }
    return error.AuthenticatedShellTimeout;
}

test "real shell prompt reconnect restores trust after worker delay" {
    var f = try Fixture.init();
    defer f.deinit();
    try f.waitBuffer("");
    const token = f.bridge.snapshot.?.token;
    f.bridge.markInput();
    try f.write("sleep 0.1\r");
    // Let line-finish send revocation and preexec close the old connection
    // before this worker next drains its bytes. The next prompt reconnects.
    for (0..80) |_| pause();
    f.bridge.synchronizeInput();
    try f.waitBuffer("");
    try std.testing.expect(f.bridge.snapshot.?.token > token);
    try std.testing.expect((try f.request(1, .begin, "")).applied);
}

test "cancelling an edit preserves authenticated transport and recovers only after real Ctrl-C prompt" {
    var f = try Fixture.init();
    defer f.deinit();
    try f.waitBuffer("");
    const token = f.bridge.snapshot.?.token;
    for (0..20) |_| pause();
    f.bridge.revoke(.integration_lost);
    try std.testing.expect(f.bridge.hello and f.bridge.snapshot == null and f.bridge.input_dirty);
    try std.testing.expectError(error.TrustedEditUnavailable, f.bridge.request(.{ .operation = 1, .kind = .begin, .token = token, .revision = 0 }, @intCast(native.zw_local_monotonic_ms())));
    try f.write("\x03");
    try f.waitBuffer("");
    try std.testing.expect(f.bridge.snapshot.?.token > token);
    const until = native.zw_local_monotonic_ms() + 2200;
    while (native.zw_local_monotonic_ms() < until) {
        try f.tick();
        try std.testing.expect(!f.bridge.disabled);
        pause();
    }
    try std.testing.expect((try f.request(1, .begin, "")).applied);
}
test "real ZLE unicode atomic replacement, lease, native history and Enter" {
    var f = try Fixture.init();
    defer f.deinit();
    try f.waitBuffer("");
    try f.write("echo '中文👩‍💻é' # original");
    try f.waitBuffer("echo '中文👩‍💻é' # original");
    const replacement = "printf '\\nZW_ONLY_AFTER_ENTER\\n' # 中文👩‍💻é";
    try std.testing.expect((try f.request(1, .replace, replacement)).applied);
    try f.waitBuffer(replacement);
    // The replaced line has not been accepted: a shell-side marker file is
    // tested below after a separate explicit Enter.
    try f.write("\x15");
    try f.waitBuffer("");
    const begin = try f.request(2, .begin, "");
    try std.testing.expect(begin.applied and begin.lease == 2);
    try std.testing.expect((try f.request(3, .end, "")).applied);
    try std.testing.expectEqual(@as(u64, 0), f.bridge.snapshot.?.lease);
    const command = try std.fmt.allocPrint(a, "cd '{s}' && printf done > marker", .{f.path});
    defer a.free(command);
    try std.testing.expect((try f.request(4, .replace, command)).applied);
    try std.testing.expectError(error.FileNotFound, f.tmp.dir.openFile(std.testing.io, "marker", .{}));
    try f.write("\r");
    try f.waitBuffer("");
    const marker = try f.tmp.dir.openFile(std.testing.io, "marker", .{});
    marker.close(std.testing.io);
    try f.write("\x1b[A");
    try f.waitBuffer(command);
}

test "Darwin ZLE exposes pending terminal bytes and queued widget input" {
    var f = try Fixture.init();
    defer f.deinit();
    try f.waitBuffer("");
    try f.write("\x18pZ");
    try f.waitBuffer("QZ");
    const file = try f.tmp.dir.openFile(std.testing.io, "pending", .{});
    defer file.close(std.testing.io);
    var bytes: [128]u8 = undefined;
    const n = try file.readPositionalAll(std.testing.io, &bytes, 0);
    var lines = std.mem.tokenizeAny(u8, bytes[0..n], "\r\n");
    const pending = try std.fmt.parseInt(u64, lines.next().?, 10);
    const queued = try std.fmt.parseInt(u64, lines.next().?, 10);
    try std.testing.expect(pending > 0);
    try std.testing.expect(queued > 0);
}

test "unchanged native input regains trust only after private observation barrier" {
    var f = try Fixture.init();
    defer f.deinit();
    try f.waitBuffer("");
    const revision = f.bridge.snapshot.?.revision;
    f.bridge.markInput();
    try f.write("\x1b[C");
    f.bridge.synchronizeInput();
    const until = native.zw_local_monotonic_ms() + 2000;
    while (f.bridge.input_dirty and native.zw_local_monotonic_ms() < until) {
        try f.tick();
        pause();
    }
    try std.testing.expect(!f.bridge.input_dirty);
    try std.testing.expectEqual(revision, f.bridge.snapshot.?.revision);
    try std.testing.expectEqualStrings("", f.bridge.snapshot.?.buffer);
}

const LocalWorker = struct {
    adapter: *@import("../adapter.zig").LocalAdapter,
    sessions: @import("../../host/session_host.zig").SessionHost,
    service: ?@import("../../host/terminal_service.zig").Service = null,
    slot_generation: u64 = 0,
    scratch: []u8,
    fn init() !LocalWorker {
        const adapter = try @import("../adapter.zig").LocalAdapter.init(a, .{});
        errdefer adapter.deinit() catch unreachable;
        return .{ .adapter = adapter, .sessions = try @import("../../host/session_host.zig").SessionHost.init(a, &.{adapter.adapter()}), .scratch = try a.alloc(u8, @import("../../vt/text_slot.zig").TextSlot.default_capacity) };
    }
    fn tick(self: *LocalWorker) !void {
        _ = try self.adapter.drain(&self.sessions);
        if (self.service) |service| {
            const slot = service.textSlot() catch |err| {
                if (err == error.WorkerBusy) return;
                return err;
            };
            if (try slot.take(self.slot_generation, self.scratch)) |frame| self.slot_generation = frame.generation;
            var bytes: [4096]u8 = undefined;
            while (true) switch (try service.readOutput(&bytes)) {
                .bytes => {},
                else => break,
            };
        }
    }
    fn deinit(self: *LocalWorker) void {
        const until = native.zw_local_monotonic_ms() + 8000;
        while (self.adapter.shutdownStep() != .released) {
            self.tick() catch {};
            if (native.zw_local_monotonic_ms() >= until) @panic("trusted worker cleanup timeout");
            pause();
        }
        self.adapter.deinit() catch unreachable;
        self.sessions.deinit();
        a.free(self.scratch);
    }
    fn editable(self: *LocalWorker, after_token: u64) !trusted.edit.Snapshot {
        const until = native.zw_local_monotonic_ms() + 3000;
        while (native.zw_local_monotonic_ms() < until) {
            try self.tick();
            if (self.service.?.trustedSnapshot(a) catch |err| {
                if (err == error.WorkerBusy) {
                    pause();
                    continue;
                }
                return err;
            }) |snapshot| {
                if (snapshot.editable() and snapshot.token > after_token) return snapshot;
                var old = snapshot;
                old.deinit(a);
            }
            pause();
        }
        return error.WorkerTrustedPromptTimeout;
    }
};

test "worker service restores empty prompt trust after Enter without another PTY input" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = ".zshenv", .data = "PROMPT=''\nRPROMPT=''\n" });
    const path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", a);
    defer a.free(path);
    const old = if (std.c.getenv("ZDOTDIR")) |v| try a.dupeSentinel(u8, std.mem.span(v), 0) else null;
    _ = setenv("ZDOTDIR", path.ptr, 1);
    defer {
        if (old) |v| {
            _ = setenv("ZDOTDIR", v.ptr, 1);
            a.free(v);
        } else _ = unsetenv("ZDOTDIR");
    }
    var worker = try LocalWorker.init();
    defer worker.deinit();
    const accepted = try worker.sessions.create(.{ .local = .{ .initial_cwd = path } }, .{ .window_id = @fromBackingInt(1), .workspace_id = @fromBackingInt(1) });
    const ready_until = native.zw_local_monotonic_ms() + 5000;
    while (native.zw_local_monotonic_ms() < ready_until) {
        try worker.tick();
        if (worker.sessions.queryService(accepted.handle, .terminal) == .available) {
            worker.service = try worker.adapter.terminalService(worker.sessions.queryService(accepted.handle, .terminal).available);
            break;
        }
        pause();
    }
    try std.testing.expect(worker.service != null);
    var first = try worker.editable(0);
    defer first.deinit(a);
    const until = native.zw_local_monotonic_ms() + 2000;
    while (true) {
        if (native.zw_local_monotonic_ms() >= until) return error.WriteTimeout;
        const status = worker.service.?.status() catch |err| {
            if (err == error.WorkerBusy) {
                pause();
                continue;
            }
            return err;
        };
        _ = worker.service.?.write(.{ .input_sequence = 1, .mode_revision = status.mode_revision, .bytes = "sleep 0.1\r" }) catch |err| {
            if (err == error.WorkerBusy) {
                pause();
                continue;
            }
            return err;
        };
        break;
    }
    // No extra key, timer-based trust reset or UI prediction is allowed here.
    var second = try worker.editable(first.token);
    defer second.deinit(a);
    try std.testing.expectEqualStrings("", second.buffer);
    const request_until = native.zw_local_monotonic_ms() + 2000;
    while (true) {
        if (native.zw_local_monotonic_ms() >= request_until) return error.BeginTimeout;
        worker.service.?.trustedRequest(.{ .operation = 1, .token = second.token, .revision = second.revision, .kind = .begin }) catch |err| {
            if (err == error.WorkerBusy) {
                pause();
                continue;
            }
            return err;
        };
        break;
    }
    const ack_until = native.zw_local_monotonic_ms() + 2000;
    while (native.zw_local_monotonic_ms() < ack_until) {
        try worker.tick();
        if (worker.service.?.trustedOutcome() catch |err| {
            if (err == error.WorkerBusy) {
                pause();
                continue;
            }
            return err;
        }) |outcome| {
            try std.testing.expect(outcome.applied and outcome.lease == 1);
            return;
        }
        pause();
    }
    return error.BeginTimeout;
}

// ---- edit temp: placement of the private ZLE directory and orphan sweep ----
extern "c" fn mkdir([*:0]const u8, c_uint) c_int;
extern "c" fn chmod([*:0]const u8, c_uint) c_int;
extern "c" fn symlink([*:0]const u8, [*:0]const u8) c_int;
extern "c" fn access([*:0]const u8, c_int) c_int;
extern "c" fn kill(c_int, c_int) c_int;
extern "c" fn getppid() c_int;
extern "c" fn mkdtemp([*:0]u8) ?[*:0]u8;
extern "c" fn system([*:0]const u8) c_int;
fn exists(path: []const u8) bool {
    var buffer: [1024]u8 = undefined;
    const z = std.fmt.bufPrintSentinel(&buffer, "{s}", .{path}, 0) catch return false;
    return access(z.ptr, 0) == 0;
}
fn writeText(dir: []const u8, name: []const u8, text: []const u8) !void {
    var buffer: [1024]u8 = undefined;
    const path = try std.fmt.bufPrintSentinel(&buffer, "{s}/{s}", .{ dir, name }, 0);
    const fd = std.c.open(path.ptr, .{ .ACCMODE = .WRONLY, .CREAT = true, .EXCL = true }, @as(std.c.mode_t, 0o600));
    if (fd < 0) return error.CreateFailed;
    defer _ = std.c.close(fd);
    if (std.c.write(fd, text.ptr, text.len) != @as(isize, @intCast(text.len))) return error.WriteFailed;
}
fn makeDir(buffer: []u8, root: []const u8, name: []const u8, mode: c_uint) ![:0]u8 {
    const path = try std.fmt.bufPrintSentinel(buffer, "{s}/{s}", .{ root, name }, 0);
    if (mkdir(path.ptr, 0o700) != 0 or chmod(path.ptr, mode) != 0) return error.MkdirFailed;
    return path;
}
fn deadPid() c_int {
    var pid: c_int = 99_998;
    while (pid > 1000) : (pid -= 1) if (kill(pid, 0) != 0 and std.c._errno().* == @intFromEnum(std.c.E.SRCH)) return pid;
    return 0;
}
fn privateScratch(buffer: *[std.c.PATH_MAX]u8) ![:0]u8 {
    const base = std.mem.span(std.c.getenv("TMPDIR") orelse return error.NoPrivateTmp);
    const template = try std.fmt.bufPrintSentinel(buffer, "{s}/zw-et-XXXXXX", .{std.mem.trimEnd(u8, base, "/")}, 0);
    _ = mkdtemp(template.ptr) orelse return error.MkdtempFailed;
    return template;
}
fn removeTree(path: []const u8) void {
    var buffer: [std.c.PATH_MAX + 16]u8 = undefined;
    const command = std.fmt.bufPrintSentinel(&buffer, "/bin/rm -rf '{s}'", .{path}, 0) catch return;
    _ = system(command.ptr);
}

test "edit temp: formal build keeps the historic /tmp template and never resolves a private root" {
    var buffer: [std.c.PATH_MAX]u8 = undefined;
    try std.testing.expect(trusted.TempRoot(false).resolve(&buffer) == null);
    var out: [256]u8 = undefined;
    try std.testing.expectEqual(@as(c_int, 0), trusted.zw_local_edit_template(null, &out, out.len));
    var expected: [64]u8 = undefined;
    try std.testing.expectEqualStrings(try std.fmt.bufPrint(&expected, "/tmp/zw-edit-{d}-XXXXXX", .{std.c.getuid()}), std.mem.sliceTo(&out, 0));
}

test "edit temp: isolated root is the private TMPDIR and long roots fall back to a tagged short path" {
    var buffer: [std.c.PATH_MAX]u8 = undefined;
    const root = trusted.TempRoot(true).resolve(&buffer) orelse return error.NoPrivateRoot;
    var real: [std.c.PATH_MAX]u8 = undefined;
    const tmpdir = std.c.realpath(std.c.getenv("TMPDIR").?, &real).?;
    try std.testing.expectEqualStrings(std.mem.span(tmpdir), std.mem.span(root));
    var out: [std.c.PATH_MAX]u8 = undefined;
    try std.testing.expectEqual(@as(c_int, 0), trusted.zw_local_edit_template("/private/tmp/zw-short", &out, out.len));
    var expected: [128]u8 = undefined;
    try std.testing.expectEqualStrings(try std.fmt.bufPrint(&expected, "/private/tmp/zw-short/zw-edit-{d}-XXXXXX", .{std.c.getuid()}), std.mem.sliceTo(&out, 0));
    const long = "/private/tmp/zw-a-very-long-private-temporary-root-that-cannot-host-a-unix-socket-path-at-all";
    try std.testing.expectEqual(@as(c_int, 0), trusted.zw_local_edit_template(long, &out, out.len));
    try std.testing.expectEqualStrings(try std.fmt.bufPrint(&expected, "/tmp/zw-edit-{d}-t{x:0>8}-XXXXXX", .{ std.c.getuid(), trusted.zw_local_edit_root_tag(long) }), std.mem.sliceTo(&out, 0));
}

test "edit temp: bridge directory is private, records its owner and is removed on deinit" {
    var buffer: [std.c.PATH_MAX]u8 = undefined;
    const root = std.mem.span(trusted.TempRoot(true).resolve(&buffer) orelse return error.NoPrivateRoot);
    var template: [std.c.PATH_MAX]u8 = undefined;
    try std.testing.expectEqual(@as(c_int, 0), trusted.zw_local_edit_template(root.ptr, &template, template.len));
    const prefix = std.mem.sliceTo(&template, 0);
    const owner: @import("../../host/identity.zig").SessionHandle = .{ .session_id = @fromBackingInt(592) };
    var bridge = try trusted.Bridge.init(a, owner);
    var directory_copy: [std.c.PATH_MAX]u8 = undefined;
    const directory = std.mem.span(bridge.bootstrap());
    @memcpy(directory_copy[0..directory.len], directory);
    {
        errdefer bridge.deinit();
        try std.testing.expect(std.mem.startsWith(u8, directory, prefix[0 .. prefix.len - 6]));
        var path: [std.c.PATH_MAX]u8 = undefined;
        const owner_path = try std.fmt.bufPrintSentinel(&path, "{s}/owner", .{directory}, 0);
        const fd = std.c.open(owner_path.ptr, .{ .ACCMODE = .RDONLY }, @as(std.c.mode_t, 0));
        try std.testing.expect(fd >= 0);
        var text: [256]u8 = undefined;
        const n = std.c.read(fd, &text, text.len);
        _ = std.c.close(fd);
        var expected: [64]u8 = undefined;
        try std.testing.expect(n > 0);
        try std.testing.expect(std.mem.startsWith(u8, text[0..@intCast(n)], try std.fmt.bufPrint(&expected, "zerowork-trusted-edit v1\npid {d}\nstart ", .{std.c.getpid()})));
        // A live owner (this process) is never swept.
        _ = trusted.zw_local_edit_sweep(root.ptr);
        try std.testing.expect(exists(directory));
    }
    bridge.deinit();
    try std.testing.expect(!exists(directory_copy[0..directory.len]));
}

test "edit temp: a terminating signal removes the live bridge directory before the process ends" {
    var fds: [2]c_int = undefined;
    try std.testing.expectEqual(@as(c_int, 0), std.c.pipe(&fds));
    const pid = std.c.fork();
    try std.testing.expect(pid >= 0);
    if (pid == 0) {
        _ = std.c.close(fds[0]);
        const owner: @import("../../host/identity.zig").SessionHandle = .{ .session_id = @fromBackingInt(593) };
        var bridge = trusted.Bridge.init(std.heap.c_allocator, owner) catch std.c._exit(3);
        const directory = std.mem.span(bridge.bootstrap());
        // The execution secret socket (secret_native.c) lives in the same directory.
        writeText(directory, "execution-secret", "") catch std.c._exit(4);
        _ = std.c.write(fds[1], directory.ptr, directory.len);
        _ = std.c.close(fds[1]);
        const no_mask: u32 = 0;
        while (true) _ = sigsuspend(&no_mask);
    }
    _ = std.c.close(fds[1]);
    var path: [std.c.PATH_MAX]u8 = undefined;
    var length: usize = 0;
    while (length < path.len) {
        const n = std.c.read(fds[0], path[length..].ptr, path.len - length);
        if (n <= 0) break;
        length += @intCast(n);
    }
    _ = std.c.close(fds[0]);
    try std.testing.expect(length > 0);
    try std.testing.expect(exists(path[0..length]));
    try std.testing.expectEqual(@as(c_int, 0), std.c.kill(pid, std.c.SIG.TERM));
    var status: c_int = 0;
    while (std.c.waitpid(pid, &status, 0) < 0) {}
    // The signal still ends the process the way it did before (default action).
    try std.testing.expect(std.c.W.IFSIGNALED(@bitCast(status)));
    try std.testing.expectEqual(std.c.SIG.TERM, std.c.W.TERMSIG(@bitCast(status)));
    try std.testing.expect(!exists(path[0..length]));
}

test "edit temp: sweep removes only provably dead ZeroWork directories" {
    var scratch_buffer: [std.c.PATH_MAX]u8 = undefined;
    const root = try privateScratch(&scratch_buffer);
    defer removeTree(root);
    const dead = deadPid();
    try std.testing.expect(dead != 0);
    const uid = std.c.getuid();
    var name: [128]u8 = undefined;
    var path: [std.c.PATH_MAX]u8 = undefined;
    var text: [512]u8 = undefined;
    const Case = struct { suffix: []const u8, removed: bool };
    const cases = [_]Case{
        .{ .suffix = "dead", .removed = true },
        .{ .suffix = "reused", .removed = true },
        .{ .suffix = "legacy", .removed = true },
        .{ .suffix = "secret", .removed = true },
        .{ .suffix = "live", .removed = false },
        .{ .suffix = "unknown", .removed = false },
        .{ .suffix = "mode", .removed = false },
        .{ .suffix = "noproof", .removed = false },
        .{ .suffix = "garbled", .removed = false },
    };
    for (cases) |case| {
        const dir = try makeDir(&path, root, try std.fmt.bufPrint(&name, "zw-edit-{d}-{s}", .{ uid, case.suffix }), if (std.mem.eql(u8, case.suffix, "mode")) 0o755 else 0o700);
        // A dead owner's secret socket path (secret_native.c) is one of the bridge's own names.
        if (std.mem.eql(u8, case.suffix, "secret")) try writeText(dir, "execution-secret", "");
        if (std.mem.eql(u8, case.suffix, "dead") or std.mem.eql(u8, case.suffix, "secret") or std.mem.eql(u8, case.suffix, "unknown") or std.mem.eql(u8, case.suffix, "mode"))
            try writeText(dir, "owner", try std.fmt.bufPrint(&text, "zerowork-trusted-edit v1\npid {d}\nstart 1.000000\n", .{dead}));
        if (std.mem.eql(u8, case.suffix, "reused"))
            try writeText(dir, "owner", try std.fmt.bufPrint(&text, "zerowork-trusted-edit v1\npid {d}\nstart 1.000000\n", .{getppid()}));
        if (std.mem.eql(u8, case.suffix, "legacy"))
            try writeText(dir, ".zshenv", try std.fmt.bufPrint(&text, "unset ZDOTDIR\ntypeset -g _zw_session=1 _zw_generation=0 _zw_parent={d} _zw_nonce='x' _zw_socket=y\n", .{dead}));
        if (std.mem.eql(u8, case.suffix, "live"))
            try writeText(dir, ".zshenv", try std.fmt.bufPrint(&text, "unset ZDOTDIR\ntypeset -g _zw_session=1 _zw_generation=0 _zw_parent={d} _zw_nonce='x' _zw_socket=y\n", .{getppid()}));
        if (std.mem.eql(u8, case.suffix, "unknown")) try writeText(dir, "notes", "user file\n");
        if (std.mem.eql(u8, case.suffix, "noproof")) try writeText(dir, "integration.zsh", "true\n");
        if (std.mem.eql(u8, case.suffix, "garbled")) try writeText(dir, "owner", "something else\n");
        writeText(dir, "integration.zsh", "") catch {};
    }
    // Wrong uid prefix and a symlink to a dead directory are never touched.
    const other = try makeDir(&path, root, try std.fmt.bufPrint(&name, "zw-edit-{d}-other", .{uid + 1}), 0o700);
    try writeText(other, "owner", try std.fmt.bufPrint(&text, "zerowork-trusted-edit v1\npid {d}\nstart 1.000000\n", .{dead}));
    const target = try makeDir(&path, root, "dead-target", 0o700);
    try writeText(target, "owner", try std.fmt.bufPrint(&text, "zerowork-trusted-edit v1\npid {d}\nstart 1.000000\n", .{dead}));
    var link: [std.c.PATH_MAX]u8 = undefined;
    try std.testing.expectEqual(@as(c_int, 0), symlink(target.ptr, (try std.fmt.bufPrintSentinel(&link, "{s}/zw-edit-{d}-link", .{ root, uid }, 0)).ptr));

    const prefix = try std.fmt.bufPrintSentinel(&name, "zw-edit-{d}-", .{uid}, 0);
    try std.testing.expectEqual(@as(c_int, 4), trusted.zw_local_edit_sweep_dir(root.ptr, prefix.ptr));
    for (cases) |case| {
        const dir = try std.fmt.bufPrint(&path, "{s}/zw-edit-{d}-{s}", .{ root, uid, case.suffix });
        try std.testing.expectEqual(!case.removed, exists(dir));
    }
    try std.testing.expect(exists(try std.fmt.bufPrint(&path, "{s}/zw-edit-{d}-other/owner", .{ root, uid + 1 })));
    try std.testing.expect(exists(try std.fmt.bufPrint(&path, "{s}/dead-target/owner", .{root})));
    try std.testing.expect(exists(try std.fmt.bufPrint(&path, "{s}/zw-edit-{d}-link", .{ root, uid })));
}
