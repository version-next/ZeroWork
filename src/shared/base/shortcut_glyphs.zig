//! 快捷键文字的唯一格式化（一致性审查 #9）：修饰键符号与显示顺序。
//!
//! 应用里的快捷键由 `features/shell/model/shortcut_router.zig` 注册与分发，提示文字都经它取；本文件只是它的
//! 底层格式化，放在 shared/base 是为了让不能依赖应用 feature 的插件（例如 KVM 的“释放键盘鼠标”）也用同一套写法。
//! 视图里不许再手写 ⌘⌃⌥⇧（check-arch 的 shortcut-text 护栏）。
const std = @import("std");

pub const command = "⌘";
pub const control = "⌃";
pub const option = "⌥";
pub const shift = "⇧";

pub const Modifier = enum { command, control, shift, option };
/// 显示顺序：与 macOS 菜单栏相同（⌃⌥⇧⌘）。键帽、提示文字、菜单栏一致。
pub const order = [_]Modifier{ .control, .option, .shift, .command };

pub const Mods = struct {
    command: bool = false,
    control: bool = false,
    shift: bool = false,
    option: bool = false,

    pub fn has(self: Mods, modifier: Modifier) bool {
        return switch (modifier) {
            .command => self.command,
            .control => self.control,
            .shift => self.shift,
            .option => self.option,
        };
    }
};

pub fn glyph(modifier: Modifier) []const u8 {
    return switch (modifier) {
        .command => command,
        .control => control,
        .shift => shift,
        .option => option,
    };
}

/// 修饰键 + 主键的整段文字（编译期）：`join(.{ .control = true, .option = true }, "Esc")` → “⌃⌥Esc”。
pub fn join(comptime mods: Mods, comptime key: []const u8) []const u8 {
    return comptime build(mods, key);
}
fn build(comptime mods: Mods, comptime key: []const u8) []const u8 {
    var value: []const u8 = "";
    for (order) |modifier| {
        if (mods.has(modifier)) value = value ++ glyph(modifier);
    }
    return value ++ key;
}

test "shortcut glyphs follow the macOS menu order" {
    try std.testing.expectEqualStrings("⌃⌥Esc", join(.{ .control = true, .option = true }, "Esc"));
    try std.testing.expectEqualStrings("⌃⌥⇧⌘K", join(.{ .command = true, .control = true, .shift = true, .option = true }, "K"));
    try std.testing.expectEqualStrings("F2", join(.{}, "F2"));
}
