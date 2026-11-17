//! “卡片已浮动”空状态的视图模型与挂载（cards-float）：视图是 `card_floated.yix`。workspace 在当前 tab 的
//! 卡片全部浮动时显示它，说明写浮动卡片的名字；“放回标签页”交回 workspace（再由浮动宿主放回原位）。
const std = @import("std");
const ui = @import("ui");
const template = @import("_card_floated.yix.zig");

pub const Vm = struct {
    icon: ui.SvgAsset = ui.icons.picture_in_picture_2,
    put_back_icon: ui.SvgAsset = ui.icons.panel_right,
    detail: *ui.Signal([]const u8),
    detail_buffers: [2][256]u8 = undefined,
    detail_slot: u1 = 0,
    ctx: ?*anyopaque = null,
    on_put_back: ?*const fn (ctx: ?*anyopaque) void = null,

    pub fn detailText(self: *const Vm) []const u8 {
        return self.detail.get();
    }
    pub fn putBack(self: *Vm) void {
        const callback = self.on_put_back orelse return;
        callback(self.ctx);
    }
};

pub const View = struct {
    vm: Vm,
    root: *ui.Node = undefined,
    names: [256]u8 = undefined,

    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, ctx: ?*anyopaque, on_put_back: *const fn (ctx: ?*anyopaque) void) !*View {
        const self = try scope.createState(View, .{ .vm = .{ .detail = try scope.createSignal([]const u8, ""), .ctx = ctx, .on_put_back = on_put_back } });
        self.root = try ui.view.render(scope, cx, template.CardFloated(.{ .vm = &self.vm }));
        return self;
    }

    /// “<名字>”浮在窗口上，会话仍在这个标签页里运行（几张卡片时写张数）。
    pub fn setFloated(self: *View, first: []const u8, count: usize) void {
        var buffer: [256]u8 = undefined;
        const text = if (count > 1)
            std.fmt.bufPrint(&buffer, "这个标签页的 {d} 张卡片都浮在窗口上，会话仍在运行。", .{count}) catch ""
        else
            std.fmt.bufPrint(&buffer, "“{s}”浮在窗口上，会话仍在这个标签页里运行。", .{first}) catch "";
        if (std.mem.eql(u8, self.vm.detail.peek(), text)) return;
        self.vm.detail_slot +%= 1;
        const slot = &self.vm.detail_buffers[self.vm.detail_slot];
        @memcpy(slot[0..text.len], text);
        self.vm.detail.set(slot[0..text.len]);
    }
};
