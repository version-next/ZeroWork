const std = @import("std");
const text_match = @import("../../../shared/base/text_match.zig");

pub const default_width: f32 = 264; // Island B v3 sidebar (Pencil JrTg7)
pub const minimum_width: f32 = 220;
pub const maximum_width: f32 = 480;

pub const Asset = struct { id: u32, name: []const u8, host: []const u8, group: []const u8 = "" };

pub const Model = struct {
    allocator: std.mem.Allocator,
    assets: std.ArrayList(Asset) = .empty,
    filtered: std.ArrayList(usize) = .empty,
    /// This window's sidebar visibility. Only the user changes it (toolbar
    /// toggle, ⌘B, or a saved change of 「默认隐藏侧栏」); window width never
    /// does (design-r3 C2).
    collapsed: bool = false,
    expanded_width: f32 = default_width,
    initial_width_pending: bool = true,
    committed_collapsed: ?bool = null,
    session_count: usize = 0,

    pub fn init(allocator: std.mem.Allocator) Model {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *Model) void {
        self.assets.deinit(self.allocator);
        self.filtered.deinit(self.allocator);
        self.* = undefined;
    }
    pub fn add(self: *Model, asset: Asset) !void {
        try self.assets.append(self.allocator, asset);
    }

    pub fn search(self: *Model, query: []const u8) ![]const usize {
        self.filtered.clearRetainingCapacity();
        for (self.assets.items, 0..) |asset, index| {
            if (text_match.matches(query, &.{ asset.name, asset.host, asset.group })) try self.filtered.append(self.allocator, index);
        }
        return self.filtered.items;
    }

    pub fn toggleCollapsed(self: *Model) void {
        self.collapsed = !self.collapsed;
    }
    /// A window's remembered (or default) visibility, applied once at mount.
    pub fn restore(self: *Model, collapsed: bool) void {
        self.collapsed = collapsed;
    }
    pub fn width(self: Model) f32 {
        return if (self.collapsed) 0 else self.expanded_width;
    }

    pub fn alignInitialWidth(self: *Model, local_right: f32, sidebar_left: f32, window_width: f32) bool {
        if (!self.initial_width_pending or !std.math.isFinite(local_right) or local_right <= sidebar_left) return false;
        const maximum = @min(maximum_width, @max(minimum_width, window_width - 480));
        const target_width = std.math.clamp(local_right - sidebar_left, minimum_width, maximum);
        self.initial_width_pending = false;
        const changed = @abs(target_width - self.expanded_width) > 0.5;
        self.expanded_width = target_width;
        return changed;
    }

    /// Session changes never override the user's sidebar choice.
    pub fn setSessionCount(self: *Model, count: usize) bool {
        self.session_count = count;
        return false;
    }
    /// The first committed value only records the baseline (the window was
    /// already restored from it or from its own memory). A later explicit
    /// settings Save that changes 「默认隐藏侧栏」 applies to the window.
    pub fn applyCommittedPreference(self: *Model, value: bool) void {
        if (self.committed_collapsed) |previous| {
            if (previous != value) self.collapsed = value;
        }
        self.committed_collapsed = value;
    }
};

test "sidebar searches assets by name host and group" {
    var model = Model.init(std.testing.allocator);
    defer model.deinit();
    try model.add(.{ .id = 1, .name = "prod-db", .host = "10.0.0.4", .group = "production" });
    try model.add(.{ .id = 2, .name = "staging", .host = "10.0.0.5", .group = "qa" });
    try std.testing.expectEqual(@as(usize, 1), (try model.search("10.0.0.4")).len);
    try std.testing.expectEqual(@as(usize, 1), (try model.search("QA")).len);
    // 共享匹配：去首尾空白、拼音首字母。
    try std.testing.expectEqual(@as(usize, 1), (try model.search("qa ")).len);
    try model.add(.{ .id = 3, .name = "生产数据库", .host = "10.0.0.6", .group = "默认分组" });
    try std.testing.expectEqual(@as(usize, 1), (try model.search("scsjk")).len);
    try std.testing.expectEqual(@as(usize, 1), (try model.search("mrfz")).len);
    model.toggleCollapsed();
    try std.testing.expectEqual(@as(f32, 0), model.width());
}

test "sidebar visibility changes only by user action, never by window width" {
    var model = Model.init(std.testing.allocator);
    defer model.deinit();
    model.restore(false);
    model.applyCommittedPreference(true);
    try std.testing.expect(!model.collapsed);
    try std.testing.expect(!model.setSessionCount(1));
    try std.testing.expectEqual(default_width, model.width());
    model.toggleCollapsed();
    try std.testing.expect(model.collapsed);
    model.applyCommittedPreference(true);
    try std.testing.expect(model.collapsed);
    model.applyCommittedPreference(false);
    try std.testing.expect(!model.collapsed);
    try std.testing.expectEqual(default_width, model.width());
    var restored = Model.init(std.testing.allocator);
    defer restored.deinit();
    restored.restore(true);
    restored.applyCommittedPreference(false);
    try std.testing.expect(restored.collapsed);
}

test "sidebar initial width aligns once and preserves a later manual width" {
    var model = Model.init(std.testing.allocator);
    defer model.deinit();
    try std.testing.expectEqual(default_width, model.width());
    try std.testing.expect(model.alignInitialWidth(402, 4, 1440));
    try std.testing.expectEqual(@as(f32, 398), model.width());
    model.expanded_width = 275;
    try std.testing.expect(!model.alignInitialWidth(242, 4, 1440));
    try std.testing.expectEqual(@as(f32, 275), model.width());

    var narrow = Model.init(std.testing.allocator);
    defer narrow.deinit();
    try std.testing.expect(narrow.alignInitialWidth(600, 4, 860));
    try std.testing.expectEqual(@as(f32, 380), narrow.width());
}
