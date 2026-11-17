//! features/update 的唯一对外门面：src/app/** 与 src/main.zig 只经由本文件引用 update 的符号。
//! 签名自 P2 起冻结；增删或改动这里的导出须走主干泳道（docs/ui-revamp/ARCHITECTURE_PLAN.md §5.1、§7）。
//! P2 阶段只做再导出：命名空间形式的导出对应 app 里按文件引用的模块，P5 再收窄为具体符号。

pub const app_host = @import("host/app_host.zig");
