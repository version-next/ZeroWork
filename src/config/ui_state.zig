//! Small per-device UI memory that is not a user setting: the main window's
//! sidebar visibility (restored on restart) and one-shot hints. It lives in the
//! private data directory (`<data>/ui-state.json`, 0600, atomic replace), next
//! to `config.toml`, so test-mode / `ZEROWORK_DATA_DIR` instances stay isolated
//! and `config.toml` only carries values the user edits in Settings.
//!
//! Every write re-reads the file and changes only its own field, so several
//! windows (one UI thread) never overwrite each other's facts. A missing or
//! unreadable file means "nothing remembered yet"; a failed write only loses
//! the memory, never blocks the UI.
const std = @import("std");
const persist = @import("../shared/base/persist.zig");

pub const file_name = "ui-state.json";

pub const State = struct {
    version: u32 = 1,
    /// Main window's last explicit sidebar choice; null = follow `ui.sidebar_collapsed`.
    main_sidebar_collapsed: ?bool = null,
    /// The user has collapsed a sidebar at least once (the narrow hint is moot).
    sidebar_collapsed_once: bool = false,
    /// The narrow-window "可以收起侧栏" hint was shown on this device.
    narrow_sidebar_hint_shown: bool = false,
};

pub fn path(allocator: std.mem.Allocator, data_directory: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ data_directory, file_name });
}

pub fn load(allocator: std.mem.Allocator, io: std.Io, file_path: []const u8) State {
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, file_path, allocator, .limited(64 * 1024)) catch return .{};
    defer allocator.free(bytes);
    const parsed = std.json.parseFromSlice(State, allocator, bytes, .{ .ignore_unknown_fields = true }) catch return .{};
    defer parsed.deinit();
    return parsed.value;
}

pub fn save(allocator: std.mem.Allocator, io: std.Io, file_path: []const u8, state: State) !void {
    const encoded = try std.json.Stringify.valueAlloc(allocator, state, .{});
    defer allocator.free(encoded);
    try persist.writeAtomic(io, std.Io.Dir.cwd(), file_path, encoded, .{ .make_path = true });
}

pub const Field = enum { main_sidebar, collapsed_once, narrow_hint };

/// Read-modify-write of one field.
pub fn update(allocator: std.mem.Allocator, io: std.Io, file_path: []const u8, field: Field, value: bool) !void {
    var state = load(allocator, io, file_path);
    switch (field) {
        .main_sidebar => state.main_sidebar_collapsed = value,
        .collapsed_once => state.sidebar_collapsed_once = value,
        .narrow_hint => state.narrow_sidebar_hint_shown = value,
    }
    try save(allocator, io, file_path, state);
}

test "ui state round trips one field at a time and tolerates a missing or broken file" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const directory = try tmp.dir.realPathFileAlloc(io, ".", a);
    defer a.free(directory);
    const file = try path(a, directory);
    defer a.free(file);
    try std.testing.expectEqualDeep(State{}, load(a, io, file));
    try update(a, io, file, .main_sidebar, true);
    try update(a, io, file, .narrow_hint, true);
    const value = load(a, io, file);
    try std.testing.expectEqual(@as(?bool, true), value.main_sidebar_collapsed);
    try std.testing.expect(value.narrow_sidebar_hint_shown);
    try std.testing.expect(!value.sidebar_collapsed_once);
    const stat = try std.Io.Dir.cwd().statFile(io, file, .{});
    try std.testing.expectEqual(@as(std.posix.mode_t, 0o600), stat.permissions.toMode() & 0o777);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = file, .data = "{not json" });
    try std.testing.expectEqualDeep(State{}, load(a, io, file));
}
