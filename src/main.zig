//! 可执行文件 zerowork 的模块根：只做转发。进程启动见 app/main.zig。
//! platform/runtime_mode.zig 经 @import("root") 读取 application_test_mode，所以它必须留在根上。
pub const application_test_mode = @import("application_options").test_mode;
pub const main = @import("app/main.zig").main;

comptime {
    // 测试构建里更新器（ZW_UPDATE_TESTING）向 platform/user_dirs 取私有家目录；正式构建不链接这个入口。
    if (application_test_mode) _ = @import("platform/user_dirs_native.zig");
    // e2e launch guards refuse any binary without this marker (platform/build_mode_marker.zig).
    if (application_test_mode) {
        const marker = @import("platform/build_mode_marker.zig");
        @export(&marker.bytes, .{ .name = marker.symbol });
    }
}
