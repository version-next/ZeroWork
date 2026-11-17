//! features/history 的唯一对外门面：src/app/** 与 src/main.zig 只经由本文件引用 history 的符号。
//! 签名自 P2 起冻结；增删或改动这里的导出须走主干泳道（docs/ui-revamp/ARCHITECTURE_PLAN.md §5.1、§7）。
//! P2 阶段只做再导出：命名空间形式的导出对应 app 里按文件引用的模块，P5 再收窄为具体符号。

/// 窗口级会话记录宿主：持有记录目录，承载本窗口全部 `history` 卡片（浮动与 tab）。
pub const HistoryHost = @import("host/history_host.zig").Host;
/// `history` 卡片类型（PL4a M1 / PL4b），由组合根登记。
pub const card_type = @import("model/card_type.zig").def;
/// 回放模型（只读回放表面 `features/terminal` 的 `ReplaySurface` 经这里取类型，跨 feature 只经门面）。
pub const Timeline = @import("model/history_replay.zig").Timeline;
pub const ReadingModel = @import("model/history_reading.zig").Model;
/// asciinema cast 解码为回放时间线（回放表面契约单测用同一条真实解码路径）。
pub const loadCast = @import("model/history_cast.zig").load;
