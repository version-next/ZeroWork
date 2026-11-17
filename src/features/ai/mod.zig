//! features/ai 的唯一对外门面：src/app/** 与 src/main.zig 只经由本文件引用 ai 的符号。
//! 签名自 P2 起冻结；增删或改动这里的导出须走主干泳道（docs/ui-revamp/ARCHITECTURE_PLAN.md §5.1、§7）。
//! P2 阶段只做再导出：命名空间形式的导出对应 app 里按文件引用的模块，P5 再收窄为具体符号。

pub const AiHost = @import("host/ai_host.zig").AiHost;
pub const mountAssistantConversation = @import("host/ai_host.zig").mountAssistantConversation;
pub const ai_assistant_header = @import("pane/view/ai_assistant_header.zig");
pub const ai_assistant_styles = @import("pane/view/ai_assistant_styles.zig");
pub const ai_card_scroll = @import("cards/view/ai_card_scroll.zig");
pub const ai_children_view = @import("sessions/view/ai_children_view.zig");
pub const ai_close_confirmation_view = @import("pane/view/ai_close_confirmation_view.zig");
pub const ai_launcher_view = @import("pane/view/ai_launcher_view.zig");
pub const ai_panel_motion_view = @import("pane/view/ai_panel_motion_view.zig");
pub const ai_sessions_view = @import("sessions/view/ai_sessions_view.zig");
pub const ai_tools = @import("tools/host/ai_tools.zig");
/// `ai.chat` 卡片类型与会话卡片的 AI 声明（PL4a M1 / M9），由组合根登记。
pub const chat_card_type = @import("pane/model/chat_card_type.zig").def;
pub const card_ai = @import("tools/host/card_ai.zig");
