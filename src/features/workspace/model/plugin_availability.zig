//! 已保存主机的协议插件是否可用（PLUGIN_ARCH_PLAN 6.2.1 Q5）：视图层经这里读本次启动的随应用插件启用状态，
//! 不直接依赖 core。被禁用的插件不在注册表里，靠“已链接插件表”把“已禁用”和“未知插件”区分开。
const std = @import("std");
const enablement = @import("../../../host/plugin_enablement.zig");

pub const Launch = enablement.Launch;
pub const Linked = enablement.Linked;

/// 侧栏主机行 Tooltip 的全文（qQaos）：原因与恢复路径。调用方释放。
pub fn reason(allocator: std.mem.Allocator, linked: Linked) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s} 已禁用，不可连接。主机配置与凭据已保留；到 偏好设置 › 协议插件 重新启用。", .{linked.display_name});
}

test "disabled host reason names the plugin and the way back" {
    const text = try reason(std.testing.allocator, .{ .id = "bmc_ikvm", .display_name = "BMC · iKVM", .plugin_version = "0.3.2" });
    defer std.testing.allocator.free(text);
    try std.testing.expect(std.mem.startsWith(u8, text, "BMC · iKVM 已禁用，不可连接"));
    try std.testing.expect(std.mem.indexOf(u8, text, "偏好设置 › 协议插件") != null);
}
