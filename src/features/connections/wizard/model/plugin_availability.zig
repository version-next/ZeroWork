//! 连接向导里被禁用的随应用插件（PLUGIN_ARCH_PLAN 6.2.1 Q5；YWqSG）：协议下拉里的禁用选项、只改通用字段的编辑。
//! 视图层经这里读本次启动的启用状态，不直接依赖 core。
const enablement = @import("../../../../host/plugin_enablement.zig");

pub const Launch = enablement.Launch;
pub const Linked = enablement.Linked;

/// 编辑已禁用插件的已保存主机时的说明（插件没有初始化，协议编辑器不可用）。
pub const edit_message = "插件没有加载，这台主机不能连接、不能测试连接。这里只能修改名称（分组可在侧栏右键“移动到分组”）；协议配置与凭据原样保留。到 偏好设置 › 协议插件 重新启用并重启后恢复。";
