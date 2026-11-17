//! 表面迁移适配器：必须保留节点的表面（终端表面、AI 对话、插件渲染面……带原生资源或昂贵状态的内容）
//! 换宿主的**唯一**入口（docs/ui-revamp/LIFECYCLE.md §2）。
//!
//! 业务状态属于模型；这里只管“同一个内容节点换一个地方显示”。Workspace、AiHost、浮动卡片宿主、
//! 保留面板都调这里，不再各自写 `detachChildRetained` + `appendChild` 再各自修焦点 / 过渡 / 身份。
//!
//! 契约（按顺序，一次调用内完成）：
//!   1. 关浮层：从表面子树里打开的 Popover / Menu / Tooltip（含它们的子菜单）先请求关闭
//!      （zenit `Cx.dismissOverlaysFrom`）——它们指向表面即将离开的位置。
//!   2. 清与旧位置绑定的输入：悬停、按下、指针捕获、进行中的拖动、滚轮会话与惯性
//!      （zenit `Cx.moveChildRetained` 内完成）。
//!   3. 迁移：节点连同子树一步换到新宿主，期间不算“被移除”。
//!   4. 属于节点自身的状态原样保留，不需要事后恢复：键盘焦点（不发 blur / focus）、原生输入会话
//!      （IME 组字继续）、文本选区（选区在失焦时才清，而焦点没有离开）、滚动位置、Scope / hook /
//!      资源、节点身份（AnchorTransition、浮层触发点、拖动绑定在迁移前拿到的 handle 继续有效）。
//!
//! 两个入口：
//!   - `move`：目的地在窗口树里。上面 1–4 全部成立。
//!   - `park`：表面离开窗口（所属面板关闭、所属 tab 关闭、宿主销毁）。这是真的移除：焦点离开
//!     （发 blur，圈焦点的浮层接手，`focusRestore` 记下丢失），身份作废。之后用 `move` 放回任意宿主。
//!
//! `move` 的目的地若不在窗口树里（宿主还没挂上），焦点按移除处理——调用方应先把宿主挂进窗口再迁移
//! （Workspace 的分屏重建就是先挂新窗格、再迁内容、最后拆旧窗格）。
//!
//! 不做的事：不决定谁拿焦点（焦点没离开就不该有人“放回去”；离开了由目的地宿主按自己的规则放）、
//! 不碰表面的显隐与尺寸（目的地宿主的布局决定）、不重建任何节点。
const std = @import("std");
const ui = @import("ui");

/// 自进程启动以来的迁移次数（预算与回归断言用，见 `lifecycle_budget.zig`）。
pub var moves: u64 = 0;
pub var parks: u64 = 0;

/// 目的地：`parent` 下、`before` 之前（null = 最后）。
pub const Host = struct {
    parent: *ui.Node,
    before: ?*ui.Node = null,
};

pub const Error = error{ CyclicNodeTree, CrossWorldNode, InvalidChildParent, InvalidAnchor, OutOfMemory };

/// 停放中的表面与它离开窗口时的主题版本：不在树里的节点收不到主题重放，放回时若主题变过就补一次
/// （`Cx.replaySubtreeTheme`）。UI 只在主线程上改树，表面数量是个位数。
const Parked = struct { surface: *ui.Node, cx: *ui.Cx, theme_version: u32 };
var parked_surfaces: std.ArrayListUnmanaged(Parked) = .empty;

fn parkedIndex(surface: *ui.Node) ?usize {
    for (parked_surfaces.items, 0..) |entry, index| if (entry.surface == surface) return index;
    return null;
}

/// 把 `surface` 迁到 `host`。已经在那里（同一父节点、不要求换位置）时什么都不做——不关浮层、不清输入。
/// 从停放状态放回时，主题在停放期间变过就先重放一次主题。
pub fn move(cx: *ui.Cx, surface: *ui.Node, host: Host) Error!void {
    if (surface.parent == host.parent and host.before == null) return;
    const was_parked = surface.parent == null;
    _ = cx.dismissOverlaysFrom(surface);
    try cx.moveChildRetained(surface, host.parent, host.before);
    moves += 1;
    if (parkedIndex(surface)) |index| {
        const entry = parked_surfaces.swapRemove(index);
        if (entry.cx == cx and entry.theme_version != cx.theme_version) cx.replaySubtreeTheme(surface);
    } else if (was_parked) {
        // 不是经 `park` 离开的（别处摘下来的、或刚建好还没挂过）：不知道它错过了什么，重放一次。
        cx.replaySubtreeTheme(surface);
    }
}

/// 表面离开窗口（保留节点与资源）。不在树里时什么都不做。
pub fn park(cx: *ui.Cx, surface: *ui.Node) void {
    const parent = surface.parent orelse return;
    // 先留好记录的位置：停放记录是“这个节点活着、且不在任何树里”的唯一凭据（`own` 靠它释放），
    // 记不下来就不停放（表面留在原处，只是多参与几帧布局）。
    if (parkedIndex(surface) == null) parked_surfaces.ensureUnusedCapacity(std.heap.c_allocator, 1) catch return;
    _ = cx.dismissOverlaysFrom(surface);
    cx.detachChildRetained(parent, surface);
    parks += 1;
    if (parkedIndex(surface) == null) parked_surfaces.appendAssumeCapacity(.{ .surface = surface, .cx = cx, .theme_version = cx.theme_version });
}

/// 表面的归属：`scope` 释放时，表面若正停放在窗口外（没有任何宿主拥有它），由这里释放；在某个宿主里时归
/// 宿主（随宿主的树释放）。每个会被停放的表面登记一次，登记在创建它的 Scope 上。
pub fn own(scope: *ui.Scope, cx: *ui.Cx, surface: *ui.Node) !void {
    const Owned = struct {
        cx: *ui.Cx,
        surface: *ui.Node,
        fn release(raw: *anyopaque, allocator: std.mem.Allocator) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            // 只有停放记录能证明节点还活着且不在任何树里；不在记录里就不碰它（可能已随宿主释放）。
            if (parkedIndex(self.surface)) |index| {
                _ = parked_surfaces.swapRemove(index);
                self.cx.freeDetachedNodeAfterScopeDispose(self.surface);
            }
            allocator.destroy(self);
        }
    };
    const owned = try scope.allocator.create(Owned);
    owned.* = .{ .cx = cx, .surface = surface };
    try scope.adoptResource(@ptrCast(owned), Owned.release);
}

/// 表面即将被销毁（或它的窗口关闭）：忘掉它的停放记录。
pub fn forget(surface: *ui.Node) void {
    if (parkedIndex(surface)) |index| _ = parked_surfaces.swapRemove(index);
}

/// 窗口关闭：忘掉这个窗口的全部停放记录。
pub fn forgetWindow(cx: *ui.Cx) void {
    var index: usize = 0;
    while (index < parked_surfaces.items.len) {
        if (parked_surfaces.items[index].cx == cx) _ = parked_surfaces.swapRemove(index) else index += 1;
    }
}

/// 诊断：`cx` 这个窗口当前停放着的表面（写进 `buffer`，返回写入的部分）。
pub fn parkedIn(cx: *ui.Cx, buffer: []*ui.Node) []*ui.Node {
    var count: usize = 0;
    for (parked_surfaces.items) |entry| if (entry.cx == cx and count < buffer.len) {
        buffer[count] = entry.surface;
        count += 1;
    };
    return buffer[0..count];
}

/// 表面当前是否停放在窗口外。
pub fn isParked(surface: *ui.Node) bool {
    return surface.parent == null;
}

/// 键盘焦点是否在表面里（宿主据此决定迁移后要不要自己放焦点：在里面就什么都不做）。
pub fn holdsFocus(cx: *ui.Cx, surface: *ui.Node) bool {
    const focused = cx.focus_manager.getFocused() orelse return false;
    return focused == surface or focused.isDescendantOf(surface);
}

/// 放置动作的按钮（放入分屏、浮动、作为标签页打开、最大化、最小化）：只改变表面显示在哪里，用指针按它不拿走
/// 键盘焦点——像窗口标题栏的按钮一样，正文里的选区、编辑中的输入框不因此失焦。键盘（Tab 到按钮再
/// 回车）照常：那时焦点本来就在按钮上。zenit 的 `pointer_down_focus = .preserve` 就是这个语义。
pub fn placementButton(button: *ui.Node) void {
    button.behavior.interaction.pointer_down_focus = .preserve;
}
