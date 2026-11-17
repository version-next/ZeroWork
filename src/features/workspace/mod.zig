//! features/workspace 的唯一对外门面：src/app/** 与 src/main.zig 只经由本文件引用 workspace 的符号。
//! 签名自 P2 起冻结；增删或改动这里的导出须走主干泳道（docs/ui-revamp/ARCHITECTURE_PLAN.md §5.1、§7）。
//! P2 阶段只做再导出：命名空间形式的导出对应 app 里按文件引用的模块，P5 再收窄为具体符号。

pub const MistChrome = @import("view/workspace_chrome.zig");
pub const group_model = @import("model/group_model.zig");
pub const multiwindow_test_routes = @import("host/multiwindow_test_routes.zig");
pub const session_export_jobs = @import("host/session_export_jobs.zig");
pub const session_menu_mod = @import("view/session_menu.zig");
pub const workspace_tab_styles = @import("view/workspace_tab_styles.zig");
pub const ws = @import("view/workspace.zig");
/// 测试卡片 `fixture.float` 的宿主（float-split，只在 -Dtest-mode=true 构建里由组合根装配）。
pub const FloatFixtureHost = @import("host/float_fixture_host.zig").Host;
/// cards-float：会话卡片（终端 / 文件 / KVM / 通用会话）的浮动宿主，每个窗口一个。
pub const SessionFloatHost = @import("host/session_float_host.zig").Host;
/// 通用会话卡片 `session`（PL4a M1），由组合根登记。
pub const session_card_type = @import("model/card_type.zig").session_def;
