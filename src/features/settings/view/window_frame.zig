//! 设置窗口（`.yix`）与宿主之间的接口（P3 3d；3f 删除旧外壳后只剩下面几样）。
//!
//! 视图只经 `vm`（信号 + 选择器 + `dispatch`）读写状态；另有两样东西还要跨过视图边界：
//! - `appearance`：外观与主题 › 背景图片的行内材质预览复用宿主的窗口材质图层（例外 S-18），
//!   `components/material_preview.zig` 经它挂载；宿主没有外观上下文时（测试夹具、预览 runner）为 null。
//! - `handles`：窗口模板挂载后交给宿主的三个节点句柄（卡片、内容岛、内容页根），都是模板里 `ref()` 建的
//!   live Ref——宿主不按 test_id 在树里找节点。
//! 滚动位置（S-5）、搜索框（S-4）、焦点（S-6）都是 view-model 的信号，这里没有它们的句柄。
const std = @import("std");
const ui = @import("ui");
const m = @import("../model/view_model.zig");
const AppearanceContext = @import("appearance_ui_context.zig").Context;

const NodeRef = *ui.view.Ref(*ui.Node);

/// 窗口模板（`settings_window.yix`）的节点句柄。Ref 归窗口模板的 Scope：窗口挂载时由模板的 `onMount` 交给
/// `Frame.keep`，窗口卸载时由 `onUnmount` 收回（`Frame.forget`）；所以只在窗口挂着的时候有值。
pub const Handles = struct {
    /// 卡片 `settings.panel`。
    panel: NodeRef,
    /// 内容岛 `settings.island`。
    island: NodeRef,
    /// 内容页根 `settings.content`。内容页按纪元重挂：旧页卸载时这个 Ref 清空，新页挂载时写入，
    /// 中间读到的是 null，不会读到已释放的节点。
    content: NodeRef,
};

pub const Frame = struct {
    vm: *m.ViewModel,
    appearance: ?*AppearanceContext = null,
    /// 窗口没挂载时为 null（只挂单个面板的测试夹具也是）。
    handles: ?Handles = null,

    /// 窗口模板 `onMount`。
    pub fn keep(self: *Frame, panel_ref: NodeRef, island_ref: NodeRef, content_ref: NodeRef) void {
        self.handles = .{ .panel = panel_ref, .island = island_ref, .content = content_ref };
    }
    /// 窗口模板 `onUnmount`：只收回这次挂载交出的句柄（同一个 Frame 可能已经交给了新的一次挂载）。
    pub fn forget(self: *Frame, panel_ref: NodeRef) void {
        if (self.handles) |handles| if (handles.panel == panel_ref) {
            self.handles = null;
        };
    }
    pub fn panel(self: *const Frame) ?*ui.Node {
        return (self.handles orelse return null).panel.get();
    }
    pub fn island(self: *const Frame) ?*ui.Node {
        return (self.handles orelse return null).island.get();
    }
};

/// 宿主持有的内容页句柄：内容页根 `settings.content`（随纪元重挂）。
pub const Page = struct {
    root: *ui.Node,

    /// 当前挂着的内容页；窗口没挂载、或内容页正在重挂（旧页已卸、新页未挂）时为 null。
    pub fn of(frame: *const Frame) ?Page {
        return .{ .root = (frame.handles orelse return null).content.get() orelse return null };
    }

    /// 重挂内容页之前交出正文里的焦点（S-6）：
    /// - 在可恢复的输入框上（`settings.field.<key>` 带 `focusId`、未禁用）：`abandonFocus` 静默交出——框架的
    ///   `focusRestore` 在这条路径上记下目标与选区，新页挂好后放回。
    /// - 在正文的其它控件上：主动 blur，让 blur 在页面回调释放前送达（它们本来就不恢复焦点）。
    pub fn releaseFocus(_: Page, cx: *ui.Cx, focused: *ui.Node) void {
        if (restorable(cx, focused)) cx.focus_manager.abandonFocus(focused) else cx.setFocus(null);
    }
    /// A form field's input: its control carries a field focus id (`focusId`, what `focusRestore`
    /// puts focus back on), it is a text input and it is enabled.
    fn restorable(cx: *ui.Cx, focused: *ui.Node) bool {
        const name = cx.focus_targets.targetName(cx, focused) orelse return false;
        return std.mem.startsWith(u8, name, m.focus_ids.legacy_field_prefix) and focused.behavior.interaction.text_input_client != null and !(if (focused.behavior.interaction.a11y) |a11y| a11y.disabled else false);
    }
};
