//! Saved-host source SVGs and 72px RGBA derivatives. See assets/host-os/README.md.
//! Geometry is only a temporary fallback before the window renderer is ready.
const ui = @import("ui");
const fallback = @import("session_os_assets.zig").linux;
fn source(comptime name: []const u8, comptime id: u16) ui.SvgAsset {
    var value = fallback;
    value.icon_id = id;
    value.svg_data = @embedFile("host-os/" ++ name ++ ".svg");
    return value;
}
pub const alpine = source("alpine", 54100);
pub const archlinux = source("archlinux", 54101);
pub const debian = source("debian", 54102);
pub const fedora = source("fedora", 54103);
pub const freebsd = source("freebsd", 54104);
pub const linux = source("linux", 54105);
pub const ubuntu = source("ubuntu", 54106);
pub const windows = source("windows", 54107);
pub const rocky = source("rocky", 54108);
pub const kylin = source("kylin", 54109);
pub const neokylin = source("neokylin", 54110);
pub const openkylin = source("openkylin", 54111);
pub const ubuntukylin = source("ubuntukylin", 54112);
pub const uos = source("uos", 54113);
pub const deepin = source("deepin", 54114);
pub const openeuler = source("openeuler", 54115);
pub const euleros = source("euleros", 54116);
pub const anolis = source("anolis", 54117);
pub const opencloudos = source("opencloudos", 54118);
pub const tencentos = source("tencentos", 54119);
pub const alinux = source("alinux", 54120);
pub const loongnix = source("loongnix", 54121);
pub const aosc = source("aosc", 54122);
pub const bclinux = source("bclinux", 54123);
pub const kylinsec = source("kylinsec", 54124);
pub const nfs = source("nfs", 54125);
pub const linx = source("linx", 54126);
pub const isoft = source("isoft", 54127);
pub const redflag = source("redflag", 54128);
pub const rhel = source("rhel", 54129);
pub const centos = source("centos", 54130);
pub const almalinux = source("almalinux", 54131);
pub const oraclelinux = source("oraclelinux", 54132);
pub const sles = source("sles", 54133);
pub const opensuse = source("opensuse", 54134);
pub const amazonlinux = source("amazonlinux", 54135);
pub const nixos = source("nixos", 54136);
pub const gentoo = source("gentoo", 54137);
pub const kali = source("kali", 54138);
pub const linuxmint = source("linuxmint", 54139);
pub const manjaro = source("manjaro", 54140);
pub const openbsd = source("openbsd", 54141);
pub const netbsd = source("netbsd", 54142);
pub const sugon = source("sugon", 54143);
pub fn index(id: u32) ?usize {
    return if (id >= 54100 and id < 54100 + pixels.len) @intCast(id - 54100) else null;
}
pub const pixels = [_][]const u8{
    @embedFile("host-os/alpine.rgba"),
    @embedFile("host-os/archlinux.rgba"),
    @embedFile("host-os/debian.rgba"),
    @embedFile("host-os/fedora.rgba"),
    @embedFile("host-os/freebsd.rgba"),
    @embedFile("host-os/linux.rgba"),
    @embedFile("host-os/ubuntu.rgba"),
    @embedFile("host-os/windows.rgba"),
    @embedFile("host-os/rocky.rgba"),
    @embedFile("host-os/kylin.rgba"),
    @embedFile("host-os/neokylin.rgba"),
    @embedFile("host-os/openkylin.rgba"),
    @embedFile("host-os/ubuntukylin.rgba"),
    @embedFile("host-os/uos.rgba"),
    @embedFile("host-os/deepin.rgba"),
    @embedFile("host-os/openeuler.rgba"),
    @embedFile("host-os/euleros.rgba"),
    @embedFile("host-os/anolis.rgba"),
    @embedFile("host-os/opencloudos.rgba"),
    @embedFile("host-os/tencentos.rgba"),
    @embedFile("host-os/alinux.rgba"),
    @embedFile("host-os/loongnix.rgba"),
    @embedFile("host-os/aosc.rgba"),
    @embedFile("host-os/bclinux.rgba"),
    @embedFile("host-os/kylinsec.rgba"),
    @embedFile("host-os/nfs.rgba"),
    @embedFile("host-os/linx.rgba"),
    @embedFile("host-os/isoft.rgba"),
    @embedFile("host-os/redflag.rgba"),
    @embedFile("host-os/rhel.rgba"),
    @embedFile("host-os/centos.rgba"),
    @embedFile("host-os/almalinux.rgba"),
    @embedFile("host-os/oraclelinux.rgba"),
    @embedFile("host-os/sles.rgba"),
    @embedFile("host-os/opensuse.rgba"),
    @embedFile("host-os/amazonlinux.rgba"),
    @embedFile("host-os/nixos.rgba"),
    @embedFile("host-os/gentoo.rgba"),
    @embedFile("host-os/kali.rgba"),
    @embedFile("host-os/linuxmint.rgba"),
    @embedFile("host-os/manjaro.rgba"),
    @embedFile("host-os/openbsd.rgba"),
    @embedFile("host-os/netbsd.rgba"),
    @embedFile("host-os/sugon.rgba"),
};

/// Selective readability helpers for source-colour artwork.
pub const display_pixels = blk: {
    var result = pixels;
    result[index(alpine.icon_id.?).?] = @embedFile("host-os/alpine-contrast.rgba");
    result[index(bclinux.icon_id.?).?] = @embedFile("host-os/bclinux-contrast.rgba");
    result[index(redflag.icon_id.?).?] = @embedFile("host-os/redflag-contrast.rgba");
    break :blk result;
};

/// Badges with opaque backgrounds use the foreground alone for state tints.
pub const status_pixels = blk: {
    var result = pixels;
    result[index(ubuntu.icon_id.?).?] = @embedFile("host-os/ubuntu-status.rgba");
    result[index(sugon.icon_id.?).?] = @embedFile("host-os/sugon-status.rgba");
    result[index(deepin.icon_id.?).?] = @embedFile("host-os/deepin-status.rgba");
    break :blk result;
};
