//! Current-session transfer display; opening/closing remains the host's action.
const std = @import("std");
const ui = @import("ui");
const S = @import("status_transfer_styles.zig");
pub const Phase = enum { idle, running, waiting, completed, failed, paused };
pub const Summary = struct {
    name: []const u8,
    percent: []const u8 = "",
    rate: []const u8 = "",
    counts: []const u8 = "",
    fraction: f32 = 0,
    upload: bool = false,
    phase: Phase = .running,
};
pub const View = struct {
    cx: *ui.Cx,
    root: *ui.Node,
    row: *ui.Node,
    name: *ui.Node,
    percent: *ui.Node,
    speed: *ui.Node,
    counts: *ui.Node,
    badge: *ui.Node,
    fill: *ui.Node,
    track: *ui.Node,
    upload: *ui.Node,
    download: *ui.Node,
    idle_icon: *ui.Node,
    base: *ui.Signal(S.ButtonStyle),
    hover: *ui.Signal(?S.ButtonStyle),
    colors: S.theme.Colors,
    /// Raised by the window's theme publication; consumed where this view repaints.
    theme_watch: @import("../../../shared/ui/theme/theme_watch.zig").ThemeWatch = .{},
    phase: Phase = .idle,
    fraction: f32 = 0,

    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, on_click: anytype) !*View {
        const self = try scope.createState(View, undefined);
        const base = try scope.createSignal(S.ButtonStyle, S.button(.idle));
        const hover = try scope.createSignal(?S.ButtonStyle, S.hover());
        const root = try ui.widgets.Button(.{ .variant = .ghost, .a11y_label = "打开传输列表", .base_style = base, .hover_style = hover, .on_click = on_click }).mount(scope, cx);
        root.meta.ownership.meta.test_id = "status.transfer";
        const row = try ui.box(cx, S.row(true), .{});
        try root.appendChild(cx.allocator, row);
        const upload = try ui.iconTint(cx, ui.icons.get("arrow-up-right").?, S.theme.current().accent, S.icon());
        const download = try ui.iconTint(cx, ui.icons.get("arrow-down-left").?, S.theme.current().accent, S.icon());
        const idle_icon = try ui.iconTint(cx, ui.icons.arrow_down_up, S.theme.current().fg_2, S.icon());
        for ([_]*ui.Node{ idle_icon, upload, download }) |icon| try row.appendChild(cx.allocator, icon);
        const name = try ui.text(cx, "传输 · 空闲", S.text(true));
        name.meta.ownership.meta.test_id = "status.transfer.name";
        try row.appendChild(cx.allocator, name);
        const percent = try ui.text(cx, "", S.text(false));
        percent.setStyleInline(cx.allocator, S.label(28));
        percent.meta.ownership.meta.test_id = "status.transfer.percent";
        try row.appendChild(cx.allocator, percent);
        const speed = try ui.text(cx, "", S.text(false));
        speed.setStyleInline(cx.allocator, S.rateLabel());
        speed.meta.ownership.meta.test_id = "status.transfer.speed";
        try row.appendChild(cx.allocator, speed);
        const badge = try ui.box(cx, S.badge(), .{});
        const counts = try ui.text(cx, "", .{ .font_size = 10, .font_weight = 400, .line_height = 1.6, .color = S.theme.current().accent, .selectable = false, .text_overflow = .ellipsis, .text_align = .center });
        counts.meta.ownership.meta.test_id = "status.transfer.counts";
        counts.setStyleInline(cx.allocator, .{ .width = .fill(), .height = .{ .px = 16 }, .flex_shrink = 0 });
        try badge.appendChild(cx.allocator, counts);
        try row.appendChild(cx.allocator, badge);
        const track = try ui.box(cx, S.track(), .{});
        track.meta.ownership.meta.test_id = "status.transfer.track";
        const fill = try ui.box(cx, S.fill(0), .{});
        fill.meta.ownership.meta.test_id = "status.transfer.fill";
        try track.appendChild(cx.allocator, fill);
        const rail = try ui.box(cx, S.rail(), .{});
        try rail.appendChild(cx.allocator, track);
        try root.appendChild(cx.allocator, rail);
        self.* = .{ .cx = cx, .root = root, .row = row, .name = name, .percent = percent, .speed = speed, .counts = counts, .badge = badge, .fill = fill, .track = track, .upload = upload, .download = download, .idle_icon = idle_icon, .base = base, .hover = hover, .colors = S.theme.current() };
        try self.theme_watch.bind(cx, scope);
        self.updateSummary(.{ .name = "传输 · 空闲", .phase = .idle });
        return self;
    }
    /// The status-bar slot this ticker is laid out for; fixtures mount it the same way as the status bar.
    pub const host_slot = @import("shell_styles.zig").statusProgressSlot;
    /// A theme publication this view has not painted yet: its owner refreshes it now instead of at its next
    /// sampling slot (the colours are applied by `updateSummary`).
    pub fn repaintDue(self: *const View) bool {
        return self.theme_watch.pending();
    }
    /// Compatibility facade for callers without a sampled speed.
    pub fn update(self: *View, name: []const u8, pct: []const u8, counts: []const u8, fraction: f32, upload: bool) void {
        self.updateSummary(.{ .name = name, .percent = pct, .counts = counts, .fraction = fraction, .upload = upload, .phase = if (pct.len == 0 and counts.len == 0) .idle else .running });
    }
    pub fn updateSummary(self: *View, summary: Summary) void {
        const colors = S.theme.current();
        const theme_changed = self.theme_watch.take();
        const idle = summary.phase == .idle;
        if (theme_changed) self.hover.set(S.hover());
        self.colors = colors;
        self.phase = summary.phase;
        self.fraction = std.math.clamp(summary.fraction, 0, 1);
        const rate = if (summary.rate.len > 0) summary.rate else if (idle) "" else @import("../../../shared/base/format.zig").rate_placeholder;
        for ([_]*ui.Node{ self.name, self.percent, self.speed, self.counts }, [_][]const u8{ std.fs.path.basename(summary.name), summary.percent, rate, summary.counts }) |node, value| {
            if (!std.mem.eql(u8, node.getText().?.content, value)) node.setTextContent(self.cx.allocator, value) catch {};
        }
        self.row.setStyleInline(self.cx.allocator, S.row(idle));
        const idle_name_width = if (idle) @ceil(self.cx.text.measureTextWidth(self.name.getText().?.content, 11, 500, false)) + 1 else 0;
        self.name.setStyleInline(self.cx.allocator, .{ .width = if (idle) .{ .px = idle_name_width } else .{ .grow = .{ .min = 0 } }, .min_width = 0, .height = .{ .px = 16 }, .flex_shrink = if (idle) 0 else 1, .overflow_hidden = true });
        if (self.name.getText()) |old| {
            var text = old;
            text.font_size = if (idle) 11 else 10.5;
            text.font_weight = if (idle) 500 else 400;
            text.line_height = 16 / text.font_size;
            text.color = if (idle) colors.fg_2 else colors.fg_1;
            text.text_overflow = if (idle) .clip else .ellipsis_smart;
            if (!std.meta.eql(old, text)) self.name.setText(text);
        }
        self.percent.setStyleInline(self.cx.allocator, S.label(if (summary.phase == .running) 28 else 36));
        self.percent.setTextColor(colors.fg_2);
        self.speed.setTextColor(colors.fg_2);
        self.counts.setTextColor(colors.accent);
        self.badge.setBackground(colors.accent.withAlpha(32));
        self.track.setBackground(colors.fg_2.withAlpha(46));
        const ink = switch (summary.phase) {
            .completed => colors.ok_ink,
            .failed => colors.danger_ink,
            .idle => colors.fg_2,
            else => colors.accent,
        };
        self.fill.setBackground(ink);
        _ = self.upload.setTint(ink);
        _ = self.download.setTint(ink);
        _ = self.idle_icon.setTint(colors.fg_2);
        self.idle_icon.setDisplay(if (idle) .flex else .none);
        self.upload.setDisplay(if (!idle and summary.upload) .flex else .none);
        self.download.setDisplay(if (!idle and !summary.upload) .flex else .none);
        for ([_]*ui.Node{ self.percent, self.track }) |node| node.setDisplay(if (idle) .none else .flex);
        self.speed.setDisplay(if (summary.phase == .running) .flex else .none);
        if (self.counts.getText()) |old| {
            var props = old;
            props.font_size = if (summary.counts.len > 2) 9 else 10;
            if (!std.meta.eql(old, props)) self.counts.setText(props);
        }
        // Geometry is declared, not measured: the button shrinks with the status bar down to its
        // floor (styles), the track spans it, and the fill is a share of the track.
        self.base.set(S.button(summary.phase));
        self.badge.setDisplay(if (idle) .none else .flex);
        self.fill.setStyleInline(self.cx.allocator, .{ .width = .{ .percent = self.fraction * 100 } });
    }
};
