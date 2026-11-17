//! 启动辅助：运行时配置与数据目录的清理、数据目录启动告警（P2 自 src/main.zig 原样拆出）。

const RuntimeConfig = @import("../config/runtime_config.zig").RuntimeConfig;
const DataPaths = @import("../config/paths.zig").Paths;

pub fn cleanupRuntimeConfig(runtime: *RuntimeConfig) void {
    const allocator = runtime.allocator;
    runtime.deinit();
    allocator.destroy(runtime);
}

pub fn cleanupDataPaths(paths: *DataPaths) void {
    const allocator = paths.allocator;
    paths.deinit();
    allocator.destroy(paths);
}
pub fn dataStartupAlert(err: anyerror, reset_pending: bool) bool {
    const Native = struct {
        extern fn zw_data_startup_alert([*:0]const u8, c_int, [*]const u8, usize) c_int;
    };
    const icon = @import("app_icon_assets").transparent;
    return Native.zw_data_startup_alert(@errorName(err), if (reset_pending) 1 else 0, icon.ptr, icon.len) != 0;
}

