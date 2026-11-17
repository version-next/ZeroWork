//! “新消息”提示的状态与挂载（视图 `ai_new_messages.yix`）。宿主每帧按跟随状态写 `setShown`；同值不触发更新。
const ui = @import("ui");
const IdSpace = @import("../../shared/view/ai_id_space.zig").IdSpace;
const template = @import("_ai_new_messages.yix.zig");

pub const View = struct {
    root: *ui.Node,
    shown: *ui.Signal(bool),

    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, on_jump: ui.Handler(void)) !*View {
        const self = try scope.createState(View, .{ .root = undefined, .shown = try scope.createSignal(bool, false) });
        self.root = try ui.view.render(scope, cx, template.NewMessages(.{ .space = IdSpace.of(scope), .shown = self.shown, .on_jump = on_jump }));
        return self;
    }

    pub fn setShown(self: *View, shown: bool) void {
        if (self.shown.peek() != shown) self.shown.set(shown);
    }
};
