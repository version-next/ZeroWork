//! features/connections 的唯一对外门面：src/app/** 与 src/main.zig 只经由本文件引用 connections 的符号。
//! 签名自 P2 起冻结；增删或改动这里的导出须走主干泳道（docs/ui-revamp/ARCHITECTURE_PLAN.md §5.1、§7）。
//! P2 阶段只做再导出：命名空间形式的导出对应 app 里按文件引用的模块，P5 再收窄为具体符号。

pub const QuickConnect = @import("quick_connect/model/quick_connect.zig").Model;
pub const QuickConnectHost = @import("quick_connect/host/quick_connect_host.zig").QuickConnectHost;
pub const Socks5Host = @import("socks/host/socks_application_host.zig").Host;
pub const WizardHost = @import("wizard/host/wizard_host.zig").WizardHost;
pub const asset_action_view = @import("assets/view/asset_action_view.zig");
pub const asset_group_host = @import("assets/host/asset_group_host.zig");
pub const connection_details_host = @import("progress/host/connection_details_host.zig");
pub const connection_details_view = @import("progress/view/connection_details_view.zig");
pub const connection_host = @import("progress/host/connection_host.zig");
pub const probe_connection_host = @import("wizard/host/probe_connection_host.zig");
pub const quick_connect_icon = @import("quick_connect/model/quick_connect_icon.zig");
pub const quick_connect_view = @import("quick_connect/view/quick_connect_view.zig");
pub const socks_background_host = @import("socks/host/socks_background_host.zig");
pub const socks_config_view = @import("socks/view/socks_config_view.zig");
pub const socks_exposure_confirm = @import("socks/view/socks_exposure_confirm.zig");
pub const socks_info_view = @import("socks/view/socks_info_view.zig");
pub const wizard_mod = @import("wizard/view/wizard.zig");
pub const wizard_probe = @import("wizard/host/wizard_probe.zig");
/// design-r3 稿 4：跳板引导（第 2 步空态与“新建跳板主机”子流程）的视图状态，供 `plugins/remote/editor.zig` 挂载（2026-11-13 追加）。
pub const jump_guide_view = @import("wizard/view/jump_guide_view.zig");
