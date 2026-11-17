//! features/shell 的唯一对外门面：src/app/** 与 src/main.zig 只经由本文件引用 shell 的符号。
//! 签名自 P2 起冻结；增删或改动这里的导出须走主干泳道（docs/ui-revamp/ARCHITECTURE_PLAN.md §5.1、§7）。
//! P2 阶段只做再导出：命名空间形式的导出对应 app 里按文件引用的模块，P5 再收窄为具体符号。

pub const AppNavHost = @import("host/nav_host.zig").AppNavHost;
pub const CollapsedSidebar = @import("view/sidebar_collapsed_view.zig").View;
pub const MenuHost = @import("host/menu_host.zig").MenuHost;
pub const mountSidebar = @import("host/chrome_mount.zig").mountSidebar;
pub const mountStatusBar = @import("host/chrome_mount.zig").mountStatusBar;
pub const mountTitleBar = @import("host/chrome_mount.zig").mountTitleBar;
/// 菜单的唯一构建与挂载入口（menus 包新增导出）：声明 `menu_spec.Entry`，经 `app_menu` 投影成原生 `W.Menu`。
pub const app_menu = @import("view/app_menu.zig");
pub const application_host_mod = @import("host/application_host.zig");
pub const background_layers = @import("view/background_layers.zig");
pub const plugin_window_host = @import("host/plugin_window_host.zig");
pub const shell_styles = @import("view/shell_styles.zig");
/// 快捷键的唯一入口（注册、分发、让位、冲突、提示文字）；其他 feature 经本门面取用（shortcuts 包新增导出）。
pub const shortcut_router = @import("model/shortcut_router.zig");
/// 菜单条目的声明与唯一的排列规则（常用在前、组间分隔、危险最后；menus 包新增导出）。
pub const menu_spec = @import("model/menu_spec.zig");
pub const sidebar_view = @import("view/sidebar_view.zig");
pub const startup_view = @import("view/startup_view.zig");
pub const status_connection_extras = @import("model/status_connection_extras.zig");
pub const status_connection_view = @import("view/status_connection_view.zig");
pub const status_detail_view = @import("view/status_detail_view.zig");
pub const status_transfer_view = @import("view/status_transfer_view.zig");
