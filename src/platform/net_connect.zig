//! Outbound TCP dial for std.Io users (std.http.Client in AI providers and fetch_url).
//!
//! std.Io.Threaded (zig 0.17 `posixConnect`) treats connect(2) EPERM as a programmer bug:
//! `errnoBug` panics in Debug builds and returns `error.Unexpected` otherwise. On macOS
//! EPERM is an ordinary refusal: a sandbox profile, the application firewall or a network
//! extension denied the dial (REQUESTS #53 — offline e2e sandboxes aborted Debug builds while
//! fetching https://models.dev/api.json). `Guarded` forwards every Io call unchanged except
//! `netConnectIp`, which dials here and maps every connect failure to a normal
//! `ConnectError` (EPERM / EACCES → AccessDenied), so callers surface it as a connect failure.
//! The dial is non-blocking with short polls, so Io cancellation still interrupts it.
const std = @import("std");
const Io = std.Io;
const IpAddress = Io.net.IpAddress;
const Threaded = Io.Threaded;
const posix = std.posix;

pub const Guarded = struct {
    base: Io,

    const table: Io.VTable = block: {
        @setEvalBranchQuota(10000);
        var value: Io.VTable = undefined;
        for (@typeInfo(Io.VTable).@"struct".field_names) |name| @field(value, name) = if (std.mem.eql(u8, name, "netConnectIp")) connect else Forward(name).function;
        break :block value;
    };

    pub fn io(self: *Guarded) Io {
        return .{ .userdata = self, .vtable = &table };
    }

    fn fromRaw(raw: ?*anyopaque) *Guarded {
        return @ptrCast(@alignCast(raw.?));
    }

    fn connect(raw: ?*anyopaque, address: *const IpAddress, options: IpAddress.ConnectOptions) IpAddress.ConnectError!Io.net.Socket {
        return connectIp(fromRaw(raw).base, address, options);
    }

    fn Forward(comptime name: []const u8) type {
        const info = @typeInfo(@typeInfo(@FieldType(Io.VTable, name)).pointer.child).@"fn";
        const R = info.return_type.?;
        return struct {
            fn P(comptime index: usize) type {
                return if (index < info.param_types.len) info.param_types[index].? else void;
            }
            fn one(raw: ?*anyopaque) R {
                const base = fromRaw(raw).base;
                return @field(base.vtable, name)(base.userdata);
            }
            fn two(raw: ?*anyopaque, b: P(1)) R {
                const base = fromRaw(raw).base;
                return @field(base.vtable, name)(base.userdata, b);
            }
            fn three(raw: ?*anyopaque, b: P(1), c: P(2)) R {
                const base = fromRaw(raw).base;
                return @field(base.vtable, name)(base.userdata, b, c);
            }
            fn four(raw: ?*anyopaque, b: P(1), c: P(2), d: P(3)) R {
                const base = fromRaw(raw).base;
                return @field(base.vtable, name)(base.userdata, b, c, d);
            }
            fn five(raw: ?*anyopaque, b: P(1), c: P(2), d: P(3), e: P(4)) R {
                const base = fromRaw(raw).base;
                return @field(base.vtable, name)(base.userdata, b, c, d, e);
            }
            fn six(raw: ?*anyopaque, b: P(1), c: P(2), d: P(3), e: P(4), f: P(5)) R {
                const base = fromRaw(raw).base;
                return @field(base.vtable, name)(base.userdata, b, c, d, e, f);
            }
            const function = switch (info.param_types.len) {
                1 => one,
                2 => two,
                3 => three,
                4 => four,
                5 => five,
                6 => six,
                else => @compileError("New std.Io ABI needs an explicit forwarder"),
            };
        };
    }
};

/// connect(2) errno → ConnectError. Every failure the kernel can report for a dial is a
/// normal error here; none of them may abort the process.
pub fn mapConnectErrno(err: posix.E) IpAddress.ConnectError {
    return switch (err) {
        // Sandbox / firewall / network-extension denial (macOS) and permission errors.
        .PERM, .ACCES => error.AccessDenied,
        .CONNREFUSED => error.ConnectionRefused,
        .CONNRESET, .CONNABORTED => error.ConnectionResetByPeer,
        .HOSTUNREACH, .HOSTDOWN => error.HostUnreachable,
        .NETUNREACH => error.NetworkUnreachable,
        .NETDOWN => error.NetworkDown,
        .TIMEDOUT => error.Timeout,
        .ADDRNOTAVAIL, .ADDRINUSE => error.AddressUnavailable,
        .AFNOSUPPORT => error.AddressFamilyUnsupported,
        .ALREADY => error.ConnectionPending,
        .NOBUFS, .NOMEM => error.SystemResources,
        .MFILE => error.ProcessFdQuotaExceeded,
        .NFILE => error.SystemFdQuotaExceeded,
        .PROTONOSUPPORT => error.ProtocolUnsupportedByAddressFamily,
        .PROTOTYPE => error.SocketModeUnsupported,
        else => error.Unexpected,
    };
}

/// Same contract as std.Io.Threaded's posix `netConnectIp`, without its errnoBug paths.
/// A supplied timeout is left to the base Io (Threaded does not implement one either).
pub fn connectIp(base: Io, address: *const IpAddress, options: IpAddress.ConnectOptions) IpAddress.ConnectError!Io.net.Socket {
    if (options.timeout != .none) return base.vtable.netConnectIp(base.userdata, address, options);
    try base.checkCancel();
    const family = Threaded.posixAddressFamily(address);
    const mode, const protocol = try Threaded.posixSocketModeProtocol(family, options.mode, options.protocol);
    const fd = while (true) {
        const rc = posix.system.socket(family, mode, protocol);
        switch (posix.errno(rc)) {
            .SUCCESS => break @as(posix.fd_t, @intCast(rc)),
            .INTR => try base.checkCancel(),
            .INVAL => return error.ProtocolUnsupportedBySystem,
            else => |err| return mapConnectErrno(err),
        }
    };
    errdefer _ = posix.system.close(fd);
    if (posix.errno(posix.system.fcntl(fd, posix.F.SETFD, @as(usize, posix.FD_CLOEXEC))) != .SUCCESS) return error.Unexpected;
    const flags = posix.system.fcntl(fd, posix.F.GETFL, @as(usize, 0));
    if (flags < 0) return error.Unexpected;
    const OFlags = @typeInfo(posix.O).@"struct".backing_integer.?;
    const nonblock: usize = @as(usize, @intCast(flags)) | @as(OFlags, @bitCast(posix.O{ .NONBLOCK = true }));
    if (posix.errno(posix.system.fcntl(fd, posix.F.SETFL, nonblock)) != .SUCCESS) return error.Unexpected;

    var storage: Threaded.PosixAddress = undefined;
    var length = Threaded.addressToPosix(address, &storage);
    switch (posix.errno(posix.system.connect(fd, &storage.any, length))) {
        .SUCCESS => {},
        .INPROGRESS, .INTR, .AGAIN => try awaitConnected(base, fd),
        else => |err| return mapConnectErrno(err),
    }
    // std.Io streams expect blocking descriptors, as Threaded hands them out.
    if (posix.errno(posix.system.fcntl(fd, posix.F.SETFL, @as(usize, @intCast(flags)))) != .SUCCESS) return error.Unexpected;
    length = @sizeOf(Threaded.PosixAddress);
    if (posix.errno(posix.system.getsockname(fd, &storage.any, &length)) != .SUCCESS) return error.Unexpected;
    return .{ .handle = fd, .address = Threaded.addressFromPosix(&storage) };
}

fn awaitConnected(base: Io, fd: posix.fd_t) IpAddress.ConnectError!void {
    while (true) {
        try base.checkCancel();
        var fds = [_]posix.pollfd{.{ .fd = fd, .events = posix.POLL.OUT, .revents = 0 }};
        const ready = posix.system.poll(&fds, 1, 50);
        if (ready < 0) switch (posix.errno(ready)) {
            .INTR, .AGAIN => continue,
            else => return error.Unexpected,
        };
        if (ready == 0) continue;
        var code: c_int = 0;
        var size: posix.socklen_t = @sizeOf(c_int);
        if (posix.errno(posix.system.getsockopt(fd, posix.SOL.SOCKET, posix.SO.ERROR, @ptrCast(&code), &size)) != .SUCCESS) return error.Unexpected;
        if (code == 0) return;
        return mapConnectErrno(@enumFromInt(code));
    }
}

test "net_connect maps sandbox EPERM and other dial refusals to ordinary errors" {
    try std.testing.expectEqual(error.AccessDenied, mapConnectErrno(.PERM));
    try std.testing.expectEqual(error.AccessDenied, mapConnectErrno(.ACCES));
    try std.testing.expectEqual(error.ConnectionRefused, mapConnectErrno(.CONNREFUSED));
    try std.testing.expectEqual(error.NetworkUnreachable, mapConnectErrno(.NETUNREACH));
    try std.testing.expectEqual(error.HostUnreachable, mapConnectErrno(.HOSTUNREACH));
    try std.testing.expectEqual(error.ConnectionResetByPeer, mapConnectErrno(.CONNABORTED));
    try std.testing.expectEqual(error.Unexpected, mapConnectErrno(.BADF));
}

test "net_connect guarded Io dials loopback and reports a refused port as an error" {
    var threaded: Threaded = .init(std.testing.allocator, .{});
    defer threaded.deinit();
    var guarded: Guarded = .{ .base = threaded.io() };
    const io = guarded.io();

    var server = try (try IpAddress.parseIp4("127.0.0.1", 0)).listen(io, .{});
    const port = server.socket.address.getPort();
    var client = try (try IpAddress.parseIp4("127.0.0.1", port)).connect(io, .{ .mode = .stream });
    const accepted = try server.accept(io);
    accepted.close(io);
    client.close(io);
    // Port now free: the kernel refuses the dial, which must come back as an error.
    server.deinit(io);
    try std.testing.expectError(error.ConnectionRefused, (try IpAddress.parseIp4("127.0.0.1", port)).connect(io, .{ .mode = .stream }));
}

test "net_connect sandbox probe: a denied outbound dial returns an error instead of aborting" {
    // Opt-in: run under a profile that denies outbound network (zw-nonet.sh). There the kernel
    // answers connect(2) with EPERM, which std.Io.Threaded would turn into an errnoBug panic.
    if (std.c.getenv("ZEROWORK_NET_DENIED_PROBE") == null) return error.SkipZigTest;
    var threaded: Threaded = .init(std.testing.allocator, .{});
    defer threaded.deinit();
    var guarded: Guarded = .{ .base = threaded.io() };
    // TEST-NET-1 (RFC 5737): never routed, so nothing leaves the machine even without the sandbox.
    const target = try IpAddress.parseIp4("192.0.2.1", 443);
    try std.testing.expectError(error.AccessDenied, target.connect(guarded.io(), .{ .mode = .stream }));
}
