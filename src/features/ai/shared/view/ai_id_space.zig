//! The test-id namespace of one AI conversation surface.
//!
//! The main assistant and a child dialog mount the same views (composer, cards, approvals …). Automation
//! tells them apart by id: a view in the child dialog names its nodes `ai.child.<rest>` where the main
//! assistant names them `ai.<rest>`. The surface decides this once, where it is mounted: `ChildDialog`
//! provides `.child` on its Scope, and every view under that Scope reads it at mount (`IdSpace.of`) and
//! names its nodes through it. Nothing renames a node afterwards and nothing looks a node up by its id.
//!
//! `id` takes the main-surface literal, so the id tooling (tools/arch/test_ids.zig) and a plain grep
//! still find every id where it is defined.
const std = @import("std");
const ui = @import("ui");

pub const IdSpace = enum {
    /// The main assistant (floating card or docked pane): ids as written.
    main,
    /// A child dialog: `ai.<rest>` becomes `ai.child.<rest>`.
    child,

    const Context = ui.reactive.Context(IdSpace);
    var child_space: IdSpace = .child;

    /// Marks `scope` (and every Scope below it) as a child dialog's surface.
    pub fn provideChild(scope: *ui.Scope) !void {
        try Context.provide(scope, &child_space);
    }

    /// The namespace of the surface `scope` belongs to.
    pub fn of(scope: *ui.Scope) IdSpace {
        return if (Context.consume(scope)) |space| space.* else .main;
    }

    /// The id of a node this surface names `key` on the main assistant.
    pub fn id(self: IdSpace, comptime key: []const u8) []const u8 {
        return switch (self) {
            .main => key,
            .child => comptime childKey(key),
        };
    }

    /// `id` for an id with runtime parts (`"ai.session.row.{d}"`), written into `buffer`.
    pub fn print(self: IdSpace, buffer: []u8, comptime format: []const u8, args: anytype) std.fmt.BufPrintError![]u8 {
        return switch (self) {
            .main => std.fmt.bufPrint(buffer, format, args),
            .child => std.fmt.bufPrint(buffer, comptime childKey(format), args),
        };
    }

    /// `print` into memory owned by `allocator`.
    pub fn alloc(self: IdSpace, allocator: std.mem.Allocator, comptime format: []const u8, args: anytype) std.mem.Allocator.Error![]u8 {
        return switch (self) {
            .main => std.fmt.allocPrint(allocator, format, args),
            .child => std.fmt.allocPrint(allocator, comptime childKey(format), args),
        };
    }

    /// `id` for an id another layer formatted for the main surface (a tool record's own id): `.main`
    /// returns `key` as it is, `.child` writes its child form into `buffer`.
    pub fn rebase(self: IdSpace, buffer: []u8, key: []const u8) std.fmt.BufPrintError![]const u8 {
        return switch (self) {
            .main => key,
            .child => blk: {
                std.debug.assert(std.mem.startsWith(u8, key, "ai.") and !std.mem.startsWith(u8, key, "ai.child."));
                break :blk try std.fmt.bufPrint(buffer, "ai.child.{s}", .{key[3..]});
            },
        };
    }

    /// Extra bytes a child id needs over the main one (for callers that size a buffer).
    pub const child_extra = "ai.child.".len - "ai.".len;

    fn childKey(comptime key: []const u8) []const u8 {
        if (!std.mem.startsWith(u8, key, "ai.")) @compileError("AI test ids start with \"ai.\": " ++ key);
        if (std.mem.startsWith(u8, key, "ai.child.")) @compileError("\"ai.child.\" is the child namespace itself; write the id directly: " ++ key);
        return "ai.child." ++ key[3..];
    }
};

test "IdSpace: main ids are the literals, child ids move under ai.child" {
    try std.testing.expectEqualStrings("ai.send", IdSpace.main.id("ai.send"));
    try std.testing.expectEqualStrings("ai.child.send", IdSpace.child.id("ai.send"));
    try std.testing.expectEqualStrings("ai.child.children", IdSpace.child.id("ai.children"));
    var buffer: [64]u8 = undefined;
    try std.testing.expectEqualStrings("ai.session.row.7", try IdSpace.main.print(&buffer, "ai.session.row.{d}", .{7}));
    try std.testing.expectEqualStrings("ai.child.session.row.7", try IdSpace.child.print(&buffer, "ai.session.row.{d}", .{7}));
    try std.testing.expectEqualStrings("ai.tool.result.2.ab", try IdSpace.main.rebase(&buffer, "ai.tool.result.2.ab"));
    try std.testing.expectEqualStrings("ai.child.tool.result.2.ab", try IdSpace.child.rebase(&buffer, "ai.tool.result.2.ab"));
    const owned = try IdSpace.child.alloc(std.testing.allocator, "ai.pending.card.{d}", .{3});
    defer std.testing.allocator.free(owned);
    try std.testing.expectEqualStrings("ai.child.pending.card.3", owned);
}

test "IdSpace: a Scope under a child dialog's Scope is in the child namespace, any other Scope is main" {
    const owner = try ui.reactive.SignalOwner.init(std.testing.allocator);
    defer owner.deinit();
    const root = try ui.Scope.init(std.testing.allocator, null, owner);
    defer root.dispose();
    const main_panel = try root.childScope();
    const dialog = try root.childScope();
    try IdSpace.provideChild(dialog);
    const row = try (try dialog.childScope()).childScope();
    try std.testing.expectEqual(IdSpace.main, IdSpace.of(root));
    try std.testing.expectEqual(IdSpace.main, IdSpace.of(main_panel));
    try std.testing.expectEqual(IdSpace.child, IdSpace.of(dialog));
    try std.testing.expectEqual(IdSpace.child, IdSpace.of(row));
}
