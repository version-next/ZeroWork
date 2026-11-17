//! The status box of a step row or a step group (Kaf7E A5 / A6): the native W.Spinner while the
//! step runs, otherwise one lucide glyph tinted by its tone (zenit tokens, follows the theme).
const std = @import("std");
const ui = @import("ui");
const visual = @import("../model/ai_step_visual.zig");
pub const Tone = visual.Tone;

pub fn ink(tone: visual.Tone, t: *const ui.ThemeTokens) ui.Color {
    const c = t.tokens.color;
    return switch (tone) {
        .neutral => c.fg_tertiary,
        .accent => c.accent,
        .success => c.success,
        .warning => c.warning,
        .danger => c.danger,
    };
}

pub const Status = struct {
    cx: *ui.Cx,
    scope: *ui.Scope,
    root: *ui.Node,
    size: f32,
    shown: ?visual.Visual = null,
    child_scope: ?*ui.Scope = null,
    /// The glyph or spinner shown now (owned by `root`).
    child: ?*ui.Node = null,

    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, size: f32, test_id: ?[]const u8) !*Status {
        const root = try ui.box(cx, .{ .width = .{ .px = size }, .height = .{ .px = size }, .flex_shrink = 0, .align_items = .center, .justify = .center }, .{});
        root.meta.ownership.meta.test_id = test_id;
        root.setHitTestVisible(false);
        const self = try scope.createState(Status, .{ .cx = cx, .scope = scope, .root = root, .size = size });
        try scope.createEffect(.{ .status = self, .publication = try cx.themeSignal() }, struct {
            fn run(ctx: anytype) void {
                _ = ctx.publication.get();
                ctx.status.retint();
            }
        }.run);
        return self;
    }
    fn retint(self: *Status) void {
        const shown = self.shown orelse return;
        if (shown.spinner) return;
        const glyph = self.child orelse return;
        _ = glyph.setTint(ink(shown.tone, self.cx.tokens));
    }
    pub fn set(self: *Status, next: visual.Visual) !void {
        if (self.shown) |shown| if (shown.spinner == next.spinner and shown.tone == next.tone and std.mem.eql(u8, shown.icon, next.icon)) return;
        self.shown = next;
        if (self.child) |child| {
            self.cx.detachChild(self.root, child);
            self.cx.destroyDetached(child);
        }
        self.child = null;
        if (self.child_scope) |old| old.dispose();
        self.child_scope = null;
        if (next.spinner) {
            const child_scope = try self.scope.childScope();
            self.child_scope = child_scope;
            const spinner = try ui.widgets.Spinner(.{ .size = self.size }).mount(child_scope, self.cx);
            try self.root.appendChild(self.cx.allocator, spinner);
            self.child = spinner;
        } else {
            const asset = ui.icons.get(next.icon) orelse ui.icons.check;
            const glyph = try ui.iconTint(self.cx, asset, ink(next.tone, self.cx.tokens), .{ .width = .{ .px = self.size }, .height = .{ .px = self.size } });
            try self.root.appendChild(self.cx.allocator, glyph);
            self.child = glyph;
        }
        self.cx.requestRedraw();
    }
};

