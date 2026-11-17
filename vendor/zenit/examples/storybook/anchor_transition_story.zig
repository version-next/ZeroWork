//! Anchor transition story (ZeroWork Z12): floating cards owned by tabs collapse into their tab
//! when another tab is selected and expand back when their tab is selected again (Dock-like
//! minimize, first tier). Click tabs quickly to see a run reverse mid-flight; turn on
//! "reduce motion" to get the fade. Design: docs/ANCHOR_TRANSITION.md.
const std = @import("std");
const ui = @import("ui");

const v = ui.view;
const W = ui.widgets;

const tab_count = 3;
const tab_anchor = [tab_count][]const u8{ "story.anchor.tab.0", "story.anchor.tab.1", "story.anchor.tab.2" };
const tab_label = [tab_count][]const u8{ "Terminal", "Files", "History" };

const Story = struct {
    cx: *ui.Cx,
    current: *ui.Signal(u8),
    /// away[i]: the card owned by tab i is collapsed (its tab is not current).
    away: [tab_count]*ui.Signal(bool),
    reduced: *ui.Signal(bool),

    fn select(self: *Story, i: u8) void {
        self.current.set(i);
        for (self.away, 0..) |sig, k| sig.set(k != i);
    }

    fn select0(self: *Story) void {
        self.select(0);
    }
    fn select1(self: *Story) void {
        self.select(1);
    }
    fn select2(self: *Story) void {
        self.select(2);
    }

    fn toggleReduced(self: *Story) void {
        const on = !self.reduced.peek();
        self.reduced.set(on);
        self.cx.reduced_motion = on;
    }
};

const S = struct {
    const root: ui.BoxStyle = .{ .width = .fill(), .height = .{ .px = 520 }, .gap = 12, .padding = ui.Padding.all(16) };
    const strip: ui.BoxStyle = .{ .direction = .row, .gap = 8, .align_items = .center };
    const stage: ui.BoxStyle = .{ .width = .fill(), .height = .{ .px = 380 }, .background = ui.Color.rgba(0, 0, 0, 10), .corner_radius = 10 };
    fn card(x: f32, y: f32, color: ui.Color) ui.BoxStyle {
        return .{
            .position = .absolute,
            .width = .{ .px = 260 },
            .height = .{ .px = 170 },
            .translate_x = x,
            .translate_y = y,
            .background = color,
            .corner_radius = 12,
            .padding = ui.Padding.all(14),
            .gap = 6,
            // A floating card's drop shadow paints outside the card: the flying snapshot must
            // still map the card itself onto the frame (no jump when the live card takes over).
            .shadow = .{ .color = ui.Color.rgba(0, 0, 0, 60), .blur = 24, .offset_y = 8 },
        };
    }
};

pub fn build(scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const state = try scope.createState(Story, .{
        .cx = cx,
        .current = try scope.createSignal(u8, 0),
        .away = .{
            try scope.createSignal(bool, false),
            try scope.createSignal(bool, true),
            try scope.createSignal(bool, true),
        },
        .reduced = try scope.createSignal(bool, false),
    });
    return v.render(scope, cx, v.col(.{ .style = S.root }, .{
        v.text(.{}, "Floating cards belong to a tab: switching tabs collapses them into their tab, switching back expands them."),
        v.row(.{ .style = S.strip }, .{
            v.box(.{ .motion_anchor = tab_anchor[0], .test_id = tab_anchor[0] }, .{W.Button(.{ .label = tab_label[0], .on_click = ui.on.call(state, Story.select0) })}),
            v.box(.{ .motion_anchor = tab_anchor[1], .test_id = tab_anchor[1] }, .{W.Button(.{ .label = tab_label[1], .on_click = ui.on.call(state, Story.select1) })}),
            v.box(.{ .motion_anchor = tab_anchor[2], .test_id = tab_anchor[2] }, .{W.Button(.{ .label = tab_label[2], .on_click = ui.on.call(state, Story.select2) })}),
            W.Button(.{ .label = "Reduce motion", .variant = .secondary, .on_click = ui.on.call(state, Story.toggleReduced) }),
        }),
        v.box(.{ .style = S.stage }, .{
            v.col(.{ .test_id = "story.anchor.card.0", .anchor_collapsed = state.away[0], .anchor_to = tab_anchor[0], .style = S.card(40, 40, ui.Color.rgb(226, 236, 255)) }, .{
                v.text(.{}, "AI chat · Terminal"),
                v.text(.{}, "Owned by the first tab."),
            }),
            v.col(.{ .test_id = "story.anchor.card.1", .anchor_collapsed = state.away[1], .anchor_to = tab_anchor[1], .style = S.card(340, 120, ui.Color.rgb(226, 248, 236)) }, .{
                v.text(.{}, "History · Files"),
                v.text(.{}, "Owned by the second tab."),
            }),
            v.col(.{ .test_id = "story.anchor.card.2", .anchor_collapsed = state.away[2], .anchor_to = tab_anchor[2], .style = S.card(180, 190, ui.Color.rgb(255, 240, 222)) }, .{
                v.text(.{}, "History · History"),
                v.text(.{}, "Owned by the third tab."),
            }),
        }),
    }));
}
