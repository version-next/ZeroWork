//! Read-only OS identification, never inferred from a hostname.
//!
//! Two sources, by host kind:
//! - SSH terminal hosts (vt/ssh_worker.zig): `command` on a separate bounded
//!   exec channel, opened only after the user's own shell channel; its output
//!   never reaches the interactive PTY.
//! - SFTP-only hosts (sftp_readonly.zig): no exec or shell request, ever.
//!   `fromSftp` combines what the SFTP connection itself exposes, in order: the
//!   server identification banner, `/etc/os-release` or `/usr/lib/os-release`
//!   read over SFTP, and the path style of the SFTP home directory. When none
//!   of them decides, the result is `.unknown`; there is no exec fallback.
const std = @import("std");
pub const Kind = enum(u8) {
    unknown,
    macos,
    linux,
    ubuntu,
    debian,
    fedora,
    arch,
    alpine,
    windows,
    freebsd,
    rocky,
    kylin,
    neokylin,
    openkylin,
    ubuntukylin,
    uos,
    deepin,
    openeuler,
    euleros,
    anolis,
    opencloudos,
    tencentos,
    alinux,
    loongnix,
    aosc,
    bclinux,
    kylinsec,
    nfs,
    linx,
    isoft,
    redflag,
    rhel,
    centos,
    almalinux,
    oraclelinux,
    sles,
    opensuse,
    amazonlinux,
    nixos,
    gentoo,
    kali,
    linuxmint,
    manjaro,
    openbsd,
    netbsd,
    sugon,
};
pub const command = "sh -c \"uname -s || exit; if test -r /etc/os-release; then cat /etc/os-release; elif test -r /usr/lib/os-release; then cat /usr/lib/os-release; fi\" || cmd /c ver";
pub fn parse(bytes: []const u8) Kind {
    var lines = std.mem.tokenizeAny(u8, bytes, "\r\n");
    var kernel: Kind = .unknown;
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t");
        if (std.mem.eql(u8, line, "Darwin")) kernel = .macos;
        if (std.mem.eql(u8, line, "Linux")) kernel = .linux;
        if (std.mem.eql(u8, line, "FreeBSD")) kernel = .freebsd;
        if (std.mem.eql(u8, line, "OpenBSD")) kernel = .openbsd;
        if (std.mem.eql(u8, line, "NetBSD")) kernel = .netbsd;
        if (std.mem.indexOf(u8, line, "Microsoft Windows") != null or std.mem.startsWith(u8, line, "MINGW") or std.mem.startsWith(u8, line, "MSYS") or std.mem.startsWith(u8, line, "CYGWIN")) return .windows;
        if (std.mem.startsWith(u8, line, "ID=")) {
            const id = std.mem.trim(u8, line[3..], " \t\"'");
            inline for (.{ "ubuntu", "debian", "fedora", "arch", "alpine", "rocky", "kylin", "neokylin", "openkylin", "ubuntukylin", "uos", "deepin", "openeuler", "euleros", "anolis", "opencloudos", "tencentos", "alinux", "loongnix", "aosc", "bclinux", "kylinsec", "nfs", "linx", "isoft", "redflag", "sugon", "rhel", "centos", "almalinux", "sles", "nixos", "gentoo", "kali", "linuxmint", "manjaro" }) |name| if (std.ascii.eqlIgnoreCase(id, name)) return @field(Kind, name);
            if (std.ascii.eqlIgnoreCase(id, "kylinos")) return .kylin;
            if (std.ascii.eqlIgnoreCase(id, "uniontech") or std.ascii.eqlIgnoreCase(id, "uniontechos")) return .uos;
            if (std.ascii.eqlIgnoreCase(id, "tencent")) return .tencentos;
            if (std.ascii.eqlIgnoreCase(id, "alibaba") or std.ascii.eqlIgnoreCase(id, "aliyun")) return .alinux;
            if (std.ascii.eqlIgnoreCase(id, "aosc-os")) return .aosc;
            if (std.ascii.eqlIgnoreCase(id, "nfsserver") or std.ascii.eqlIgnoreCase(id, "nfsdesktop")) return .nfs;
            if (std.ascii.eqlIgnoreCase(id, "redflag-linux")) return .redflag;
            if (std.ascii.eqlIgnoreCase(id, "ol")) return .oraclelinux;
            if (std.ascii.eqlIgnoreCase(id, "sled")) return .sles;
            inline for (.{ "opensuse", "opensuse-leap", "opensuse-tumbleweed", "opensuse-microos", "opensuse-slowroll" }) |name| if (std.ascii.eqlIgnoreCase(id, name)) return .opensuse;
            if (std.ascii.eqlIgnoreCase(id, "amzn")) return .amazonlinux;
            if (std.ascii.eqlIgnoreCase(id, "freebsd")) return .freebsd;
            if (std.ascii.eqlIgnoreCase(id, "openbsd")) return .openbsd;
            if (std.ascii.eqlIgnoreCase(id, "netbsd")) return .netbsd;
            if (id.len > 0 and kernel == .unknown) kernel = .linux;
        }
    }
    return kernel;
}

test "OS identification recognizes the reported Kylin V11 server release" {
    try std.testing.expectEqual(Kind.kylin, parse(
        "Linux\n" ++
            "NAME=\"Kylin Linux Advanced Server\"\n" ++
            "VERSION=\"V11 (Swan25)\"\n" ++
            "ID=\"kylin\"\n" ++
            "VERSION_ID=\"V11\"\n" ++
            "PRETTY_NAME=\"Kylin Linux Advanced Server V11 (Swan25)\"\n",
    ));
}

test "OS identification distinguishes domestic distributions from their upstream families" {
    const cases = .{
        .{ Kind.kylin, "ID=Kylin\nID_LIKE=debian\n" },
        .{ Kind.neokylin, "ID=\"neokylin\"\nID_LIKE=\"rhel fedora\"\n" },
        .{ Kind.openkylin, "ID=openkylin\nID_LIKE=debian\n" },
        .{ Kind.ubuntukylin, "ID=ubuntukylin\nID_LIKE=ubuntu\n" },
        .{ Kind.uos, "ID=Uos\nID_LIKE=debian\n" },
        .{ Kind.uos, "ID=UnionTechOS\nID_LIKE=\"rhel centos fedora\"\n" },
        .{ Kind.deepin, "ID=deepin\nID_LIKE=debian\n" },
        .{ Kind.openeuler, "ID=\"openEuler\"\nID_LIKE=\"rhel centos fedora\"\n" },
        .{ Kind.euleros, "ID=euleros\n" },
        .{ Kind.anolis, "ID=\"anolis\"\nID_LIKE=\"rhel fedora centos\"\n" },
        .{ Kind.opencloudos, "ID=\"opencloudos\"\n" },
        .{ Kind.tencentos, "ID=\"tencentos\"\n" },
        .{ Kind.tencentos, "ID=tencent\n" },
        .{ Kind.alinux, "ID=alinux\nID_LIKE=\"rhel fedora centos\"\n" },
        .{ Kind.alinux, "ID=alibaba\n" },
        .{ Kind.loongnix, "ID=Loongnix\nID_LIKE=debian\n" },
        .{ Kind.aosc, "ID=aosc\n" },
        .{ Kind.bclinux, "ID=bclinux\n" },
        .{ Kind.kylinsec, "ID=kylinsec\n" },
        .{ Kind.nfs, "ID=nfsserver\n" },
        .{ Kind.linx, "ID=linx\n" },
        .{ Kind.isoft, "ID=isoft\n" },
        .{ Kind.redflag, "ID=redflag\n" },
        .{ Kind.sugon, "NAME=\"Sugon OS\"\nVERSION=\"8.9\"\nID=\"sugon\"\nID_LIKE=\"rhel fedora centos\"\nVERSION_ID=\"8.9\"\nPLATFORM_ID=\"platform:sga8\"\nPRETTY_NAME=\"Sugon OS 8.9\"\n" },
        .{ Kind.sugon, "ID=SUGON\n" },
    };
    inline for (cases) |case| try std.testing.expectEqual(case[0], parse("Linux\n" ++ case[1]));
    try std.testing.expectEqual(Kind.linux, parse("Linux\nID=custom\nID_LIKE=\"openEuler kylin uos\"\n"));
    try std.testing.expectEqual(Kind.linux, parse("Linux\nID=kylin-custom\n"));
    try std.testing.expectEqual(Kind.unknown, parse("Welcome to Kylin Linux Advanced Server\n"));
}
/// The SSH identification string ("SSH-2.0-<software> <comments>", RFC 4253
/// 4.2). Only explicit vendor markers decide; a bare "OpenSSH_9.6" is unknown.
/// Debian/Ubuntu packaging tags are also shipped by derivatives (UOS, Kylin,
/// Deepin...), so `fromSftp` lets a readable os-release refine them.
pub fn parseBanner(banner: []const u8) Kind {
    const line = std.mem.trim(u8, banner, " \t\r\n");
    if (!std.mem.startsWith(u8, line, "SSH-")) return .unknown;
    var buffer: [256]u8 = undefined;
    const lower = std.ascii.lowerString(buffer[0..@min(line.len, buffer.len)], line[0..@min(line.len, buffer.len)]);
    if (std.mem.indexOf(u8, lower, "for_windows") != null or std.mem.indexOf(u8, lower, "winsshd") != null) return .windows;
    // Distribution tags live in the comments after the software version.
    var words = std.mem.tokenizeAny(u8, lower, " \t");
    _ = words.next();
    while (words.next()) |word| {
        inline for (.{ .{ "ubuntu", Kind.ubuntu }, .{ "debian", Kind.debian }, .{ "raspbian", Kind.linux }, .{ "freebsd", Kind.freebsd }, .{ "netbsd", Kind.netbsd } }) |case| {
            if (std.mem.startsWith(u8, word, case[0])) return case[1];
        }
    }
    return .unknown;
}
/// Windows SFTP servers report drive-letter paths ("/C:/Users/me", "C:\\Users").
/// Any other path style is not evidence of a particular OS.
pub fn parseSftpPath(path: []const u8) Kind {
    const rest = if (std.mem.startsWith(u8, path, "/")) path[1..] else path;
    if (rest.len < 2 or !std.ascii.isAlphabetic(rest[0]) or rest[1] != ':') return .unknown;
    if (rest.len == 2 or rest[2] == '/' or rest[2] == '\\') return .windows;
    return .unknown;
}
/// Only a banner naming a system without os-release ends SFTP detection early.
pub fn bannerIsFinal(kind: Kind) bool {
    return switch (kind) {
        .windows, .freebsd, .netbsd, .openbsd, .macos => true,
        else => false,
    };
}
/// SFTP-only evidence, strongest last-resort ordering: banner, then os-release
/// (exact ID refines a Debian/Ubuntu packaging tag), then path style.
pub fn fromSftp(banner: Kind, os_release: Kind, path_style: Kind) Kind {
    if (bannerIsFinal(banner)) return banner;
    if (os_release != .unknown) {
        // os-release alone defaults an unlisted ID to generic Linux; keep the
        // more specific banner tag then.
        if (os_release == .linux and banner != .unknown) return banner;
        return os_release;
    }
    if (banner != .unknown) return banner;
    return path_style;
}

test "SFTP OS identification uses banner, os-release and path style without exec" {
    try std.testing.expectEqual(Kind.ubuntu, parseBanner("SSH-2.0-OpenSSH_9.6p1 Ubuntu-3ubuntu13.5\r\n"));
    try std.testing.expectEqual(Kind.debian, parseBanner("SSH-2.0-OpenSSH_9.2p1 Debian-2+deb12u3"));
    try std.testing.expectEqual(Kind.windows, parseBanner("SSH-2.0-OpenSSH_for_Windows_9.5"));
    try std.testing.expectEqual(Kind.freebsd, parseBanner("SSH-2.0-OpenSSH_9.7 FreeBSD-20240806"));
    try std.testing.expectEqual(Kind.netbsd, parseBanner("SSH-2.0-OpenSSH_9.0 NetBSD_Secure_Shell-20220604"));
    try std.testing.expectEqual(Kind.unknown, parseBanner("SSH-2.0-OpenSSH_9.8"));
    try std.testing.expectEqual(Kind.unknown, parseBanner("SSH-2.0-paramiko_5.1.0"));
    try std.testing.expectEqual(Kind.unknown, parseBanner("Ubuntu"));
    try std.testing.expectEqual(Kind.windows, parseSftpPath("/C:/Users/me"));
    try std.testing.expectEqual(Kind.windows, parseSftpPath("D:\\data"));
    try std.testing.expectEqual(Kind.windows, parseSftpPath("/C:"));
    try std.testing.expectEqual(Kind.unknown, parseSftpPath("/home/me"));
    try std.testing.expectEqual(Kind.unknown, parseSftpPath("/"));
    try std.testing.expectEqual(Kind.unknown, parseSftpPath("/ab:c"));
    // os-release read over SFTP has no `uname -s` line.
    try std.testing.expectEqual(Kind.freebsd, parse("NAME=FreeBSD\nID=freebsd\n"));
    try std.testing.expectEqual(Kind.uos, fromSftp(.debian, parse("ID=uos\nID_LIKE=debian\n"), .unknown));
    try std.testing.expectEqual(Kind.ubuntu, fromSftp(.ubuntu, parse("ID=custom\n"), .unknown));
    try std.testing.expectEqual(Kind.ubuntu, fromSftp(.ubuntu, .unknown, .unknown));
    try std.testing.expectEqual(Kind.windows, fromSftp(.windows, .linux, .unknown));
    try std.testing.expectEqual(Kind.rocky, fromSftp(.unknown, parse("ID=\"rocky\"\n"), .unknown));
    try std.testing.expectEqual(Kind.windows, fromSftp(.unknown, .unknown, .windows));
    try std.testing.expectEqual(Kind.unknown, fromSftp(.unknown, .unknown, .unknown));
}
pub fn local() Kind {
    return switch (@import("builtin").os.tag) {
        .macos => .macos,
        .linux => .linux,
        .windows => .windows,
        .freebsd => .freebsd,
        .openbsd => .openbsd,
        .netbsd => .netbsd,
        else => .unknown,
    };
}
test "OS identification uses kernel and exact distribution ID" {
    try std.testing.expectEqual(Kind.macos, parse("Darwin\n"));
    try std.testing.expectEqual(Kind.ubuntu, parse("Linux\nNAME=\"Ubuntu\"\nID=ubuntu\n"));
    try std.testing.expectEqual(Kind.debian, parse("Linux\nID=\"debian\"\n"));
    try std.testing.expectEqual(Kind.rocky, parse("Linux\nID=rocky\n"));
    try std.testing.expectEqual(Kind.rocky, parse("Linux\nID=\"rocky\"\nID_LIKE=\"rhel centos fedora\"\n"));
    try std.testing.expectEqual(Kind.linux, parse("Linux\nID=unlisted\nID_LIKE=rocky\n"));
    try std.testing.expectEqual(Kind.windows, parse("Microsoft Windows [Version 10.0]\r\n"));
    try std.testing.expectEqual(Kind.unknown, parse("Ubuntu server banner\n"));
}

test "OS identification distinguishes international distributions and BSD kernels" {
    const cases = .{
        .{ Kind.rhel, "Linux\nID=rhel\nID_LIKE=fedora\n" },
        .{ Kind.centos, "Linux\nNAME=CentOS Stream\nID=centos\nID_LIKE=rhel fedora\n" },
        .{ Kind.almalinux, "Linux\nID=almalinux\nID_LIKE=rhel centos fedora\n" },
        .{ Kind.oraclelinux, "Linux\nID=ol\nID_LIKE=fedora\n" },
        .{ Kind.sles, "Linux\nID=sles\nID_LIKE=suse\n" },
        .{ Kind.sles, "Linux\nID=sled\nID_LIKE=suse\n" },
        .{ Kind.opensuse, "Linux\nID=opensuse-leap\nID_LIKE=suse opensuse\n" },
        .{ Kind.opensuse, "Linux\nID=opensuse-tumbleweed\n" },
        .{ Kind.opensuse, "Linux\nID=opensuse-microos\n" },
        .{ Kind.opensuse, "Linux\nID=opensuse-slowroll\n" },
        .{ Kind.amazonlinux, "Linux\nID=amzn\nVERSION_ID=2023\nID_LIKE=fedora\n" },
        .{ Kind.nixos, "Linux\nID=nixos\n" },
        .{ Kind.gentoo, "Linux\nID=gentoo\n" },
        .{ Kind.kali, "Linux\nID=kali\nID_LIKE=debian\n" },
        .{ Kind.linuxmint, "Linux\nID=linuxmint\nID_LIKE=ubuntu debian\n" },
        .{ Kind.manjaro, "Linux\nID=Manjaro\nID_LIKE=arch\n" },
        .{ Kind.openbsd, "OpenBSD\n" },
        .{ Kind.netbsd, "NetBSD\n" },
    };
    inline for (cases) |case| try std.testing.expectEqual(case[0], parse(case[1]));
    try std.testing.expectEqual(Kind.linux, parse("Linux\nID=custom\nID_LIKE=rhel centos opensuse\n"));
    try std.testing.expectEqual(Kind.linux, parse("Linux\nID=almalinux-custom\n"));
    try std.testing.expectEqual(Kind.unknown, parse("Welcome to Amazon Linux and OpenBSD\n"));
    // A release file must not turn a known non-Linux kernel into Linux.
    try std.testing.expectEqual(Kind.freebsd, parse("FreeBSD\nID=freebsd\n"));
}
