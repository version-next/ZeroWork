//! features/notifications 的唯一对外门面：src/app/** 与 src/main.zig 只经由本文件引用 notifications 的符号。
//! 签名自 P2 起冻结；增删或改动这里的导出须走主干泳道（docs/ui-revamp/ARCHITECTURE_PLAN.md §5.1、§7）。
//! P2 阶段只做再导出：命名空间形式的导出对应 app 里按文件引用的模块，P5 再收窄为具体符号。
//!
//! native-notify 新增（待主干泳道确认）：窗口级原生通知栈的宿主胶水与它的 view-model 类型——其他 feature
//! （终端的命令失败提示、文件 / 传输 / 菜单的本地回执、窗口宿主）经这里接入，不再直接引用本 feature 的内部文件。

pub const NotificationWindowHook = @import("host/notification_window_hook.zig").NotificationWindowHook;
/// The title-bar bell's history panel (the shell's click group closes it when another tool opens).
pub const NotificationHistoryView = @import("view/notification_history.zig").View;
const presenter = @import("host/notification_presenter.zig");
/// 每个应用窗口一个：挂两个原生通知栈——右上角卡片栈（协调器提醒、命令失败提示）、中下方标准 Toast（本地回执）。
pub const NotificationPresenter = presenter.Presenter;
pub const NotificationPlacement = presenter.Placement;
/// 本地操作成功的回执（已复制、目录已刷新）：本窗口中下方标准 Toast 里的一条原生文字提示。
pub const acknowledgeAt = presenter.acknowledgeAt;
/// 窗口通知的 view-model 类型（`cards` / `toasts` 两条通道；命令失败提示用 `Card` / `CommandEvent` / `showCommand`，进卡片栈）。
pub const toast = @import("model/view_model.zig");
/// 本窗口通知的 view-model（两条通道；没有挂载时为 null）。
pub fn windowToasts(cx: anytype) ?*toast.ViewModel {
    const p = presenter.Presenter.forWindow(cx) orelse return null;
    return &p.vm;
}
