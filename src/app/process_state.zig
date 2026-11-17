//! 进程级全局状态（P2 自 src/main.zig 原样拆出）：进程窗口表、偏好设置窗口槽位与所有者、字体注册表、通知宿主。

const FontRegistry = @import("zenit_app").FontRegistry;
const NotificationHost = @import("../host/notification_host.zig").Host;
const ProcessWindows = @import("process_windows.zig").ProcessWindows;
const SettingsHost = @import("../features/settings/mod.zig").SettingsHost;

pub var process_windows: ?*ProcessWindows = null;
/// The single preferences window (Island B v3 `p6ZVS`), an auxiliary window
/// (shared/ui/window/aux_window.zig) whose client is the SettingsHost that opened it.
pub var settings_window_slot: @import("../shared/ui/window/aux_window.zig").Slot = .{ .spec = @import("../features/settings/mod.zig").settings_shell.window_spec, .client = undefined };
pub var settings_window_owner: ?*SettingsHost = null;
pub var app_font_registry: ?*FontRegistry = null;
pub var process_notifications: ?*NotificationHost = null;
