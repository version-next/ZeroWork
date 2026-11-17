//! 打开中的会话菜单：哪一种（`Kind`）与打开时捕获的上下文。键盘导航、高亮与选中都是原生 `W.Menu` 的事
//! （menus 包删去了手画菜单的 `selected_index` / `move` / `handle`）。
const std = @import("std");
const menus = @import("context_menus.zig");

pub const Trigger = enum { terminal_middle_click, terminal_right_click, host_right_click, session_banner, tab_right_click };
pub const State = struct {
    open: ?menus.Kind = null,
    context: menus.Context = .{},

    pub fn dismiss(self: *State) void {
        self.open = null;
    }

    pub fn show(self: *State, kind: menus.Kind, context: menus.Context) void {
        self.open = kind;
        self.context = context;
        // Session-ended menus force their own flag so .reconnect enables.
        if (kind == .session_ended) self.context.session_ended = true;
    }
};

pub fn kindFor(trigger: Trigger) menus.Kind {
    return switch (trigger) {
        .terminal_middle_click, .terminal_right_click => .terminal,
        .host_right_click => .host_asset,
        .session_banner => .session_ended,
        .tab_right_click => .tab,
    };
}

test "menu trigger routing keeps contexts separate" {
    try std.testing.expectEqual(menus.Kind.terminal, kindFor(.terminal_middle_click));
    try std.testing.expectEqual(menus.Kind.terminal, kindFor(.terminal_right_click));
    try std.testing.expectEqual(menus.Kind.host_asset, kindFor(.host_right_click));
    try std.testing.expectEqual(menus.Kind.session_ended, kindFor(.session_banner));
    try std.testing.expectEqual(menus.Kind.tab, kindFor(.tab_right_click));
}

test "session-ended menus enable reconnect; dismiss clears the kind" {
    var state: State = .{};
    state.show(.session_ended, .{});
    try std.testing.expect(state.context.session_ended);
    try std.testing.expect(menus.isEnabled(.reconnect, state.context));
    state.dismiss();
    try std.testing.expect(state.open == null);
}
