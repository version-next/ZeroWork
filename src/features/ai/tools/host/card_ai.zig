//! 会话卡片的 AI 声明（PLUGIN_ARCH_PLAN 2.5.8 M9）：AI 能力只在卡片类型上配置。
//!
//! `terminal`、`file` 的放置约束由各自的 feature 声明，这里给出它们的 AI 部分，组合根把两者合成一个
//! 卡片类型登记。上下文由会话所属协议的引擎组装（今天的 `assembleContext`），工具取会话所属插件
//! 登记的工具、由同一引擎执行。细节宿主工具按名字引用。
//!
//! `host.tab_context` 的查询参数（ai-followup）也由卡片类型自己声明并实现（`CardAi.query`）：
//! - 终端：`max_lines` 取最近 N 行输出，`limit` 取最近 N 条 shell 命令（命令文本、结束状态）；
//!   不支持 `cursor`（逐段续读用 `host.read_terminal` 的游标）。
//! - 文件：`limit` 取远端当前目录的最多 N 个目录项，`cursor` 从上一页的 `next_cursor` 续读；
//!   不支持 `max_lines`。
//! 都只读 UI 线程上的内存快照，不发起连接、不读文件内容。实现放在各自的会话引擎文件里（终端：
//! `ai_local_tools.zig` 的 `terminalCardQuery`，本机与 SSH 终端共用；文件：`ai_file_tools.zig` 的
//! `fileCardQuery`），因为只有它们能访问应用宿主与文件工作区。
const card_types = @import("../../../../host/card_types.zig");

pub const terminal: card_types.CardAi = .{
    .summary = .session_engine,
    .tools = .{ .session_tools = &.{
        .{ .plugin_id = "local", .factory = @import("ai_local_tools.zig").createAdapter },
        .{ .plugin_id = "ssh", .factory = @import("ai_ssh_tools.zig").createAdapter },
    } },
    .host_tools = &.{ "host.read_terminal", "host.search_terminal", "host.list_terminal_commands" },
    .query = .{
        .max_lines = "the summary shows the most recent N terminal output lines (history depth)",
        .limit = "the summary lists the most recent N shell commands with their exit status",
        .note = "Terminal cards page with host.read_terminal's cursor, not with host.tab_context.",
        .run = @import("ai_local_tools.zig").terminalCardQuery,
    },
};

pub const file: card_types.CardAi = .{
    .summary = .session_engine,
    .tools = .{ .session_tools = &.{
        .{ .plugin_id = "sftp", .factory = @import("ai_file_tools.zig").createAdapter },
    } },
    .query = .{
        .limit = "the summary lists at most N entries of the current remote directory (default 50)",
        .cursor = "continue that directory listing from an entry's next_cursor",
        .note = "File cards list directory entries; read file contents with the card's detail_tools.",
        .run = @import("ai_file_tools.zig").fileCardQuery,
    },
};

/// 合成登记用的卡片类型：feature 声明的放置约束 + 这里的 AI 声明。
pub fn withAi(def: card_types.CardTypeDef, ai: card_types.CardAi) card_types.CardTypeDef {
    var result = def;
    result.ai = ai;
    return result;
}
