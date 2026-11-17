//! 预览 runner 与原生夹具的多路复用构建根（docs/ui-revamp/ARCHITECTURE_PLAN.md §5.1、§5.4；
//! YIX_SPIKE.md V-1：模块根文件不能 import 自身目录之外的文件，所以构建根必须留在 src/ 根目录）。
//!
//! build.zig 为每个预览步骤注入具名模块 `root_select`（`name` = 产物名），这里在 comptime 选出
//! 实现文件并转发 std 与仓库代码会从根模块读取的声明。没被选中的分支只做语法解析，不做语义分析，
//! 其中用到的具名模块（`ui`、`zenit_app` …）不要求在本次构建里存在。步骤名、产物名、链接配置不变。
const std = @import("std");
const name = @import("root_select").name;

fn is(comptime candidate: []const u8) bool {
    return comptime std.mem.eql(u8, name, candidate);
}

const Impl = if (is("settings-preview-runner"))
    @import("features/settings/preview/settings_preview_runner.zig")
else if (is("file-workspace-preview"))
    @import("features/files/preview/file_workspace_native_fixture.zig")
else if (is("auth-challenge-preview"))
    @import("features/connections/auth/preview/auth_challenge_native_fixture.zig")
else if (is("connection-progress-preview"))
    @import("features/connections/progress/preview/connection_progress_preview_runner.zig")
else if (is("transfer-events-preview"))
    @import("features/transfer/preview/transfer_events_native_fixture.zig")
else if (is("transfer-conflict-preview"))
    @import("features/transfer/preview/transfer_conflict_native_fixture.zig")
else if (is("transfer-controls-preview"))
    @import("features/transfer/preview/transfer_controls_preview_runner.zig")
else if (is("notification-preview"))
    @import("features/notifications/preview/notification_preview_runner.zig")
else if (is("bmc-kvm-preview"))
    @import("plugins/bmc_ikvm/preview/bmc_kvm_preview_runner.zig")
else if (is("task-finish-preview"))
    @import("features/ai/cards/preview/task_finish_preview_runner.zig")
else if (is("execution-result-preview"))
    @import("features/ai/cards/preview/execution_result_preview_runner.zig")
else if (is("inventory-grant-preview"))
    @import("features/ai/approvals/preview/inventory_grant_preview_runner.zig")
else if (is("close-confirmation-preview"))
    @import("features/ai/pane/preview/ai_close_confirmation_preview_runner.zig")
else if (is("ai-empty-recent-preview"))
    @import("features/ai/sessions/preview/ai_empty_recent_preview_runner.zig")
else if (is("ai-recovery-preview"))
    @import("features/ai/cards/preview/ai_recovery_preview_runner.zig")
else if (is("ai-launcher-preview"))
    @import("features/ai/pane/preview/ai_launcher_preview_runner.zig")
else if (is("composer-interaction-preview"))
    @import("features/ai/composer/preview/composer_interaction_preview_runner.zig")
else if (is("button-policy-preview"))
    @import("shared/ui/preview/button_policy_preview_runner.zig")
else if (is("forward-config-preview"))
    @import("features/connections/socks/preview/forward_config_preview_runner.zig")
else if (is("socks-info-preview"))
    @import("features/connections/socks/preview/socks_info_preview_runner.zig")
else
    @compileError("src/preview.zig: unknown preview '" ++ name ++ "'");

// ── 根级声明转发（与 src/acceptance.zig 保持一致）────────────────────
// 缺省值与“根文件没有该声明”时的行为相同：std.options 缺省为 `.{}`；
// platform/runtime_mode.zig 只在 `application_test_mode` 存在且为 true 时开启自动化。
pub fn main(init: std.process.Init) !void {
    if (!@hasDecl(Impl, "main")) @compileError("src/preview.zig: '" ++ name ++ "' has no main");
    try @import("platform/user_dirs.zig").requireIsolatedStartup();
    return Impl.main(init);
}
pub const std_options: std.Options = if (@hasDecl(Impl, "std_options")) Impl.std_options else .{};
pub const application_test_mode = if (@hasDecl(Impl, "application_test_mode")) Impl.application_test_mode else false;
/// 预览与夹具从不进入正式 App：家目录一律按测试构建隔离（platform/user_dirs.zig），
/// 并认 ZEROWORK_DATA_DIR；没有私有 HOME 就拒绝启动。
pub const zerowork_isolated_home = true;

comptime {
    // 被选中的实现若声明了其他会被 std / zenit 从根模块读取的声明，必须在这里补转发，否则会被静默忽略。
    for ([_][]const u8{ "panic", "os", "debug", "tracy", "build_options", "zenit_web_glass", "std_options_debug_io", "std_options_debug_threaded_io", "std_options_cwd", "std_options_FilePermissions", "std_options_elf_debug_info_search_paths" }) |decl| {
        if (@hasDecl(Impl, decl)) @compileError("src/preview.zig: forward root declaration '" ++ decl ++ "' for '" ++ name ++ "'");
    }
    _ = Impl;
}

comptime {
    // -Dtest-mode=true builds carry the launch-guard marker (platform/build_mode_marker.zig).
    if (@import("root_select").test_mode) {
        const marker = @import("platform/build_mode_marker.zig");
        @export(&marker.bytes, .{ .name = marker.symbol });
    }
}
