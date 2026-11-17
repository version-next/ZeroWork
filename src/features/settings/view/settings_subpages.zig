//! Settings drill-down map, view side. The data (slugs, titles, pane ids,
//! keys, summaries) lives in `model/catalog.zig`; this file only maps the
//! catalog's icon ids to `ui` assets for the overview hero and rows.
//!
//! A category with subpages opens on an overview (hero + one row per subpage);
//! a subpage shows only the panes listed in the catalog, which are the existing
//! sections of that category's page module, matched by their test ids.
//! Categories without subpages (快捷键 / 协议插件 / 关于与更新) render all
//! panes directly, as in the design.
const std = @import("std");
const ui = @import("ui");
const catalog = @import("../model/catalog.zig");
const pages = catalog.pages;

pub const Summary = catalog.Summary;
pub const Subpage = catalog.Subpage;
pub const Category = catalog.Category;
pub const IconId = catalog.IconId;

/// In `settings_pages.pages` order.
pub const categories = catalog.categories;

/// The `ui` asset of a catalog icon (enum names are `ui.icons` declarations).
pub fn iconAsset(id: IconId) ui.SvgAsset {
    return switch (id) {
        inline else => |tag| @field(ui.icons, @tagName(tag)),
    };
}

pub const subpages = catalog.subpages;
pub const hasOverview = catalog.hasOverview;
pub const get = catalog.get;
/// Whether a pane (section test id) belongs on the subpage.
pub const contains = catalog.contains;
/// The subpage that edits `section.key`, for jumping to a validation problem.
pub const forKey = catalog.forKey;

pub const Location = catalog.Location;
pub const History = catalog.History;

test "every documented setting key belongs to exactly one subpage of its category" {
    for (pages.keys) |entry| {
        var page: usize = 0;
        for (pages.pages, 0..) |candidate, index| if (std.mem.eql(u8, candidate.name, entry.page)) {
            page = index;
        };
        if (!hasOverview(page)) continue;
        var found: usize = 0;
        var buffer: [96]u8 = undefined;
        const name = try std.fmt.bufPrint(&buffer, "{s}.{s}", .{ entry.section, entry.key });
        for (subpages(page)) |subpage| for (subpage.keys) |candidate| {
            if (std.mem.eql(u8, candidate, name)) found += 1;
        };
        std.testing.expectEqual(@as(usize, 1), found) catch |err| {
            std.debug.print("unmapped or duplicated setting {s}\n", .{name});
            return err;
        };
    }
    try std.testing.expectEqual(@as(?u8, 1), forKey(2, "ssh", "socks_port"));
    try std.testing.expectEqual(@as(?u8, null), forKey(1, "ssh", "socks_port"));
}

