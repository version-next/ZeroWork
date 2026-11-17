//! features/terminal 的唯一对外门面：src/app/** 与 src/main.zig 只经由本文件引用 terminal 的符号。
//! 签名自 P2 起冻结；增删或改动这里的导出须走主干泳道（docs/ui-revamp/ARCHITECTURE_PLAN.md §5.1、§7）。
//! P2 阶段只做再导出：命名空间形式的导出对应 app 里按文件引用的模块，P5 再收窄为具体符号。

pub const applyResolvedTerminalTypography = @import("host/typography.zig").applyResolvedTerminalTypography;
pub const terminalFamilyId = @import("host/typography.zig").terminalFamilyId;
pub const command_help_view = @import("view/_command_help.yix.zig");
pub const command_history_view = @import("view/command_history_view.zig");
pub const local_close_view = @import("view/local_close_view.zig");
pub const local_status_view = @import("view/local_status_view.zig");
/// `terminal` 卡片类型的放置约束（PL4a M1），由组合根登记。
pub const card_type = @import("model/card_type.zig").def;
/// 只读回放表面（PL4b H2）：会话记录卡片的详情区经这里嵌入归档模式的终端视图；接口冻结，见文件内契约单测。
pub const ReplaySurface = @import("view/replay_surface.zig").ReplaySurface;
