//! Per-window sidebar memory and the one-time narrow-window hint (design-r3 C2, 稿 2 ①).
//!
//! - The sidebar never collapses by itself; only the user toggles it. Each window
//!   keeps its own state. The main window's state is remembered in the private
//!   data directory (`config/ui_state.zig`) and restored on restart; other
//!   windows (opened for a connection, not restored at launch) start from the
//!   `ui.sidebar_collapsed` setting 「默认隐藏侧栏」 and keep their own state in memory.
//! - The first time the content area cannot fit two minimum-width split cards
//!   while the sidebar is shown, one info toast (bottom centre, no actions) suggests collapsing it.
//!   Once per device; never after the user has collapsed a sidebar.
const std = @import("std");
const ui_state = @import("../../../config/ui_state.zig");
const applog = @import("../../../platform/applog.zig");
/// Same value as `workspace/model/group_layout.zig` `min_card_width` (稿 2: 每张终端卡片最小宽 320);
/// kept local because features only meet through their facades.
const min_card_width: f32 = 320;

/// Two minimum cards + split gap 4 + island inset 12 (稿 2: 2 × 320 + 4 + 12 = 656).
pub const narrow_content_width: f32 = 2 * min_card_width + 4 + 12;
/// One line (native text toast, max 480 wide): the title plus where the switch is.
pub const hint_text = "窗口较窄，可以收起侧栏 · 点标题栏左侧的侧栏开关";
pub const hint_duration_ms: u32 = 8_000;

pub const Memory = struct {
    /// `<data>/ui-state.json`; null when the window has no data directory (tests).
    path: ?[]u8 = null,
    /// Only the main window persists its sidebar state.
    remember: bool = false,
    state: ui_state.State = .{},
    /// This window already decided about the hint (posted or suppressed).
    hint_done: bool = false,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, data_directory: []const u8) !Memory {
        const file = try ui_state.path(allocator, data_directory);
        return .{ .path = file, .state = ui_state.load(allocator, io, file) };
    }

    pub fn deinit(self: *Memory, allocator: std.mem.Allocator) void {
        if (self.path) |value| allocator.free(value);
        self.* = .{};
    }

    /// The main window's remembered visibility (null: follow the setting).
    pub fn remembered(self: *const Memory) ?bool {
        return if (self.remember) self.state.main_sidebar_collapsed else null;
    }

    /// Record a user-made visibility change of this window.
    pub fn changed(self: *Memory, allocator: std.mem.Allocator, io: std.Io, collapsed: bool) void {
        const file = self.path orelse return;
        if (self.remember and self.state.main_sidebar_collapsed != collapsed) {
            self.state.main_sidebar_collapsed = collapsed;
            ui_state.update(allocator, io, file, .main_sidebar, collapsed) catch |err| applog.warn(.ui, "sidebar state: {s}", .{@errorName(err)});
        }
        if (collapsed and !self.state.sidebar_collapsed_once) {
            self.state.sidebar_collapsed_once = true;
            ui_state.update(allocator, io, file, .collapsed_once, true) catch |err| applog.warn(.ui, "sidebar state: {s}", .{@errorName(err)});
        }
    }

    /// Whether this frame should post the narrow-window hint. Re-reads the
    /// device memory before saying yes, so another window's hint counts.
    pub fn wantsHint(self: *Memory, allocator: std.mem.Allocator, io: std.Io, collapsed: bool, content_width: f32) bool {
        if (self.hint_done) return false;
        if (self.state.narrow_sidebar_hint_shown or self.state.sidebar_collapsed_once) {
            self.hint_done = true;
            return false;
        }
        if (!shouldHint(collapsed, content_width)) return false;
        const file = self.path orelse return false;
        self.state = ui_state.load(allocator, io, file);
        if (self.state.narrow_sidebar_hint_shown or self.state.sidebar_collapsed_once) {
            self.hint_done = true;
            return false;
        }
        return true;
    }

    pub fn hinted(self: *Memory, allocator: std.mem.Allocator, io: std.Io) void {
        self.hint_done = true;
        self.state.narrow_sidebar_hint_shown = true;
        const file = self.path orelse return;
        ui_state.update(allocator, io, file, .narrow_hint, true) catch |err| applog.warn(.ui, "sidebar hint state: {s}", .{@errorName(err)});
    }
};

/// Pure trigger: sidebar shown and the measured content area is narrower than two cards.
pub fn shouldHint(collapsed: bool, content_width: f32) bool {
    return !collapsed and content_width > 0 and content_width < narrow_content_width;
}

test "narrow hint triggers only with the sidebar shown below two minimum cards" {
    try std.testing.expectEqual(@as(f32, 656), narrow_content_width);
    try std.testing.expect(shouldHint(false, 584));
    try std.testing.expect(!shouldHint(true, 584));
    try std.testing.expect(!shouldHint(false, 836));
    try std.testing.expect(!shouldHint(false, 0));
}

test "sidebar memory persists only the main window and shows the hint once per device" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const directory = try tmp.dir.realPathFileAlloc(io, ".", a);
    defer a.free(directory);
    var main = try Memory.init(a, io, directory);
    defer main.deinit(a);
    main.remember = true;
    var other = try Memory.init(a, io, directory);
    defer other.deinit(a);
    try std.testing.expectEqual(@as(?bool, null), main.remembered());
    // The first narrow frame in either window posts once; the other window sees it.
    try std.testing.expect(main.wantsHint(a, io, false, 584));
    main.hinted(a, io);
    try std.testing.expect(!main.wantsHint(a, io, false, 584));
    try std.testing.expect(!other.wantsHint(a, io, false, 584));
    other.changed(a, io, true);
    var restarted = try Memory.init(a, io, directory);
    defer restarted.deinit(a);
    restarted.remember = true;
    try std.testing.expectEqual(@as(?bool, null), restarted.remembered());
    try std.testing.expect(restarted.state.sidebar_collapsed_once);
    main.changed(a, io, true);
    var again = try Memory.init(a, io, directory);
    defer again.deinit(a);
    again.remember = true;
    try std.testing.expectEqual(@as(?bool, true), again.remembered());
}

test "collapsing a sidebar before any narrow frame suppresses the hint" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const directory = try tmp.dir.realPathFileAlloc(io, ".", a);
    defer a.free(directory);
    var memory = try Memory.init(a, io, directory);
    defer memory.deinit(a);
    memory.changed(a, io, true);
    memory.changed(a, io, false);
    try std.testing.expect(!memory.wantsHint(a, io, false, 584));
}
