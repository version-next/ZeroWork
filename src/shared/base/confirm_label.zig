//! 确认按钮文案：动词 + 对象（CONSISTENCY_AUDIT #2；用户拍板 2：“按钮文案用‘动词 + 对象’，比如‘删除主机’”）。
//! 只有这些动词；对象紧跟其后。界面入口见 `shared/ui/confirm/confirm.zig`。
const std = @import("std");

/// 确认按钮只用这些动词（后面紧跟对象）。
pub const Verb = enum {
    close,
    end,
    delete,
    clear,
    replace,
    disconnect,
    stop,
    discard,
    install,
    retry,
    new,
    restore,
    use,
    expose,

    pub fn text(self: Verb) []const u8 {
        return switch (self) {
            .close => "关闭",
            .end => "结束",
            .delete => "删除",
            .clear => "清空",
            .replace => "替换",
            .disconnect => "断开",
            .stop => "停止",
            .discard => "放弃",
            .install => "安装",
            .retry => "重试",
            .new => "新建",
            .restore => "恢复",
            .use => "使用",
            .expose => "开放",
        };
    }
};

/// “动词 + 对象”（编译期拼好）：`label(.delete, "主机")` = “删除主机”。
pub inline fn label(comptime verb: Verb, comptime object: []const u8) []const u8 {
    if (object.len == 0) @compileError("confirm.label: the object is required (动词 + 对象)");
    return comptime verb.text() ++ object;
}

/// 运行期对象（带数量等）：写进 `buffer`，例如 `labelFmt(&buf, .close, "{d} 个会话", .{n})`。
pub fn labelFmt(buffer: []u8, comptime verb: Verb, comptime object: []const u8, args: anytype) []const u8 {
    return std.fmt.bufPrint(buffer, verb.text() ++ object, args) catch verb.text();
}

/// 全应用只有这一个取消文案。
pub const cancel_label = "取消";

test "confirm labels: verb + object" {
    try std.testing.expectEqualStrings("删除主机", label(.delete, "主机"));
    var buffer: [32]u8 = undefined;
    try std.testing.expectEqualStrings("关闭 2 个会话", labelFmt(&buffer, .close, " {d} 个会话", .{2}));
}
