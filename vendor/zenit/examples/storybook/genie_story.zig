//! Genie story: a window minimizes into its Dock icon the way macOS does (ZeroWork Z12, the
//! static-texture model). While a run is in flight only one cached picture of the card is drawn:
//! the card itself is out of layout and paint, and the picture is warped on the GPU through a mesh
//! pulled into the icon by its near edge. Switch the picture to "Path + scale" (the first tier,
//! also what renderers without a mesh composite draw) or "Fade", slow it down to see the mesh, and
//! click again mid-run to reverse. Design: docs/ANCHOR_TRANSITION.md.
const std = @import("std");
const ui = @import("ui");

const v = ui.view;
const W = ui.widgets;
const fx = ui.fx.anchor_transition;

const dock_anchor = [2][]const u8{ "story.genie.dock.0", "story.genie.dock.1" };

fn tokensFor(shape: u8, slow: bool) fx.Tokens {
    var t: fx.Tokens = switch (shape) {
        1 => fx.affine_tokens,
        2 => fx.fade_scale_tokens,
        else => fx.default_tokens,
    };
    if (slow) {
        // Five times slower, every duration alike.
        t.genie_collapse_duration_s *= 5;
        t.genie_expand_duration_s *= 5;
        t.collapse_duration_s *= 5;
        t.expand_duration_s *= 5;
        t.fade_scale_out_duration_s *= 5;
        t.fade_scale_in_duration_s *= 5;
    }
    return t;
}

const Story = struct {
    minimized: [2]*ui.Signal(bool),
    /// 0 = genie, 1 = path + scale, 2 = fade.
    shape: *ui.Signal(u8),
    slow: *ui.Signal(bool),
    motion: *ui.Signal(fx.Tokens),

    fn sync(self: *Story) void {
        self.motion.set(tokensFor(self.shape.peek(), self.slow.peek()));
    }
    fn toggle0(self: *Story) void {
        self.minimized[0].set(!self.minimized[0].peek());
    }
    fn toggle1(self: *Story) void {
        self.minimized[1].set(!self.minimized[1].peek());
    }
    fn genie(self: *Story) void {
        self.shape.set(0);
        self.sync();
    }
    fn affine(self: *Story) void {
        self.shape.set(1);
        self.sync();
    }
    fn fade(self: *Story) void {
        self.shape.set(2);
        self.sync();
    }
    fn toggleSlow(self: *Story) void {
        self.slow.set(!self.slow.peek());
        self.sync();
    }
};

const S = struct {
    const root: ui.BoxStyle = .{ .width = .fill(), .height = .{ .px = 560 }, .gap = 12, .padding = ui.Padding.all(16) };
    const bar: ui.BoxStyle = .{ .direction = .row, .gap = 8, .align_items = .center };
    const desk: ui.BoxStyle = .{ .width = .fill(), .height = .{ .px = 440 }, .background = ui.Color.rgba(0, 0, 0, 10), .corner_radius = 10 };
    const dock: ui.BoxStyle = .{
        .position = .absolute,
        .direction = .row,
        .gap = 10,
        .padding = ui.Padding.all(8),
        .translate_x = 220,
        .translate_y = 372,
        .background = ui.Color.rgba(255, 255, 255, 180),
        .corner_radius = 14,
    };
    fn icon(color: ui.Color) ui.BoxStyle {
        return .{ .width = .{ .px = 44 }, .height = .{ .px = 44 }, .corner_radius = 10, .background = color };
    }
    fn window(x: f32, y: f32, tint: ui.Color) ui.BoxStyle {
        return .{
            .position = .absolute,
            .width = .{ .px = 300 },
            .height = .{ .px = 210 },
            .translate_x = x,
            .translate_y = y,
            .background = ui.Color.rgb(252, 252, 252),
            .corner_radius = 12,
            .gap = 8,
            .shadow = .{ .color = ui.Color.rgba(0, 0, 0, 70), .blur = 24, .offset_y = 8 },
            .border = .{ .width = 1, .color = tint },
        };
    }
    fn titlebar(tint: ui.Color) ui.BoxStyle {
        return .{ .width = .fill(), .height = .{ .px = 28 }, .background = tint, .padding = .{ .left = 12, .top = 6 } };
    }
    const content: ui.BoxStyle = .{ .padding = .{ .left = 12, .right = 12 }, .gap = 6 };
};

const blue = ui.Color.rgb(90, 140, 230);
const orange = ui.Color.rgb(235, 150, 70);

pub fn build(scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const state = try scope.createState(Story, .{
        .minimized = .{ try scope.createSignal(bool, false), try scope.createSignal(bool, false) },
        .shape = try scope.createSignal(u8, 0),
        .slow = try scope.createSignal(bool, false),
        .motion = try scope.createSignal(fx.Tokens, fx.default_tokens),
    });
    return v.render(scope, cx, v.col(.{ .style = S.root }, .{
        v.text(.{}, "Click a Dock icon to minimize its window into it (genie) and again to restore it. Only one cached picture flies; the window itself is out of layout and paint until it lands."),
        v.row(.{ .style = S.bar }, .{
            v.attrs(.{ .test_id = "story.genie.shape.genie" }, W.Button(.{ .label = "Genie", .on_click = ui.on.call(state, Story.genie) })),
            v.attrs(.{ .test_id = "story.genie.shape.affine" }, W.Button(.{ .label = "Path + scale", .variant = .secondary, .on_click = ui.on.call(state, Story.affine) })),
            v.attrs(.{ .test_id = "story.genie.shape.fade" }, W.Button(.{ .label = "Fade", .variant = .secondary, .on_click = ui.on.call(state, Story.fade) })),
            v.attrs(.{ .test_id = "story.genie.slow" }, W.Button(.{ .label = "Slow motion", .variant = .secondary, .on_click = ui.on.call(state, Story.toggleSlow) })),
        }),
        v.box(.{ .style = S.desk }, .{
            v.col(.{ .test_id = "story.genie.window.0", .anchor_collapsed = state.minimized[0], .anchor_to = dock_anchor[0], .anchor_motion = state.motion, .style = S.window(40, 30, blue) }, .{
                v.box(.{ .style = S.titlebar(blue) }, .{v.text(.{}, "Terminal")}),
                v.col(.{ .style = S.content }, .{
                    v.text(.{}, "$ zig build test"),
                    v.text(.{}, "All 104 tests passed."),
                    v.text(.{}, "$ _"),
                }),
            }),
            v.col(.{ .test_id = "story.genie.window.1", .anchor_collapsed = state.minimized[1], .anchor_to = dock_anchor[1], .anchor_motion = state.motion, .style = S.window(380, 60, orange) }, .{
                v.box(.{ .style = S.titlebar(orange) }, .{v.text(.{}, "Notes")}),
                v.col(.{ .style = S.content }, .{
                    v.text(.{}, "Genie: the edge facing the Dock pinches first,"),
                    v.text(.{}, "the sides bend, then the strip slides in."),
                }),
            }),
            v.row(.{ .style = S.dock }, .{
                v.box(.{ .motion_anchor = dock_anchor[0], .test_id = dock_anchor[0], .style = S.icon(blue), .on_click = ui.on.call(state, Story.toggle0) }, .{}),
                v.box(.{ .motion_anchor = dock_anchor[1], .test_id = dock_anchor[1], .style = S.icon(orange), .on_click = ui.on.call(state, Story.toggle1) }, .{}),
            }),
        }),
    }));
}
