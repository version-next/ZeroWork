//! Subscription to a window's theme publication for views that repaint imperatively.
//!
//! A view whose colours come from tokens / named style functions needs nothing: zenit replays
//! them. A view that still has to run its own repaint (retained nodes painted with plain styles,
//! rebuilt rows) subscribes here instead of comparing the palette on every frame: the window's
//! publication (theme, material transparency, blur) raises the flag once, and the view consumes
//! it at its own safe point (its layout hook, its next update).
const std = @import("std");
const ui = @import("ui");

pub const ThemeWatch = struct {
    state: ?*State = null,

    const State = struct { pending: bool = true };

    /// Subscribes to `cx`'s theme publication for the lifetime of `scope`. The first `take`
    /// after binding is true (the view has not painted this theme yet).
    pub fn bind(self: *ThemeWatch, cx: *ui.Cx, scope: *ui.Scope) !void {
        const state = try scope.createState(State, .{});
        try scope.createEffect(.{ .state = state, .cx = cx, .publication = try cx.themeSignal() }, struct {
            fn published(ctx: anytype) void {
                _ = ctx.publication.get();
                ctx.state.pending = true;
                ctx.cx.requestRedraw();
            }
        }.published);
        self.state = state;
    }

    /// True once per publication: the caller repaints now. Never true while unbound.
    pub fn take(self: *ThemeWatch) bool {
        const state = self.state orelse return false;
        const raised = state.pending;
        state.pending = false;
        return raised;
    }

    /// Whether a publication is waiting, without consuming it.
    pub fn pending(self: *const ThemeWatch) bool {
        return if (self.state) |state| state.pending else false;
    }
};

test "ThemeWatch raises once per theme publication and never between them" {
    const theme = @import("app_theme.zig");
    const previous = theme.currentName();
    defer theme.select(previous);
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    cx.root = try ui.box(cx, .{}, .{});
    const publication = try cx.bindState(@import("theme_publication.zig").ThemePublication, .{});
    publication.publish(cx, theme.widgetTheme(theme.currentName()));
    var watch: ThemeWatch = .{};
    try watch.bind(cx, scope);
    try std.testing.expect(watch.take());
    for (0..5) |_| {
        _ = cx.render();
        try std.testing.expect(!watch.pending());
        try std.testing.expect(!watch.take());
    }
    // Same palette published again (a material parameter changed): still one notification.
    publication.publish(cx, theme.widgetTheme(theme.currentName()));
    _ = cx.render();
    try std.testing.expect(watch.take());
    try std.testing.expect(!watch.take());
    theme.select(if (previous == .dark) .light else .dark);
    // Selecting a palette without publishing it to the window is not a theme change of the window.
    _ = cx.render();
    try std.testing.expect(!watch.take());
    publication.publish(cx, theme.widgetTheme(theme.currentName()));
    _ = cx.render();
    try std.testing.expect(watch.take());
}
