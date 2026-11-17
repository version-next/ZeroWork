//! 协议插件的路线条目（`docs/plugins/PLUGIN_ARCH_PLAN.md` 2.6；6.2.1 的 Q1）。
//!
//! "计划中"不是清单上的 `status` 字段，而是这张与 `PluginManifest` 类型分离的表：条目只有名字、目标版本、
//! 设计文档路径和图标，没有能力、版本号、ABI 或权限，也不能创建会话（协议选择器、会话宿主、工具目录只接受
//! `PluginManifest`）。规则：
//! - 只列仓库里有设计文档的条目（单测校验 `design_doc` 存在）；
//! - 条目 `id` 与任何已注册插件冲突时 `PluginHost.publish` 失败（`error.RoadmapConflict`），
//!   所以实现落地的那个提交必须同时删掉对应条目，条目不会过期。
//!
//! 位置说明：方案草图写的是 `src/plugins/roadmap.zig`，但设置的 model 层不能 import `src/plugins`
//! （check-arch 的 `layer:model->plugin_registry`），而注册表的 `publish` 在 core，所以放在 core 的 `src/host`。
const std = @import("std");

pub const RoadmapEntry = struct {
    /// 将来实现时插件要用的 ID（与已注册插件冲突即注册失败）。
    id: []const u8,
    display_name: []const u8,
    /// 目标版本，设置页显示为"{target} 版本待实施"。
    target: []const u8,
    /// 仓库内的设计文档（相对仓库根）。
    design_doc: []const u8,
    /// `ui.icons` 的图标名。
    icon: []const u8,
};

pub const entries = [_]RoadmapEntry{
    .{ .id = "web", .display_name = "网页连接", .target = "0.5", .design_doc = "docs/DESIGN/V0.5_WEB_CONNECTION.md", .icon = "globe" },
};

pub fn find(id: []const u8) ?RoadmapEntry {
    for (entries) |entry| if (std.mem.eql(u8, entry.id, id)) return entry;
    return null;
}

test "roadmap entries are unique and point at design documents in the repository" {
    for (entries, 0..) |entry, i| {
        try std.testing.expect(entry.id.len != 0 and entry.display_name.len != 0 and entry.target.len != 0 and entry.icon.len != 0);
        for (entries[0..i]) |earlier| try std.testing.expect(!std.mem.eql(u8, earlier.id, entry.id));
        // 测试在仓库根运行（zig build test）；没有设计文档的"计划"不能上界面。
        _ = try std.Io.Dir.cwd().statFile(std.testing.io, entry.design_doc, .{});
    }
}

test "roadmap lists only the web connection; retired planned protocols are gone" {
    try std.testing.expectEqual(@as(usize, 1), entries.len);
    try std.testing.expectEqualStrings("0.5", find("web").?.target);
    // KVM 已由 `bmc_ikvm` 实现；FTP / FTPS、VNC、RDP 没有设计文档（6.2.1 Q1）。
    for ([_][]const u8{ "kvm", "bmc_ikvm", "ftp_ftps", "ftps", "vnc", "rdp" }) |id| try std.testing.expect(find(id) == null);
}
