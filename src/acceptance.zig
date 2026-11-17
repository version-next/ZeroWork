//! 非 UI 验收 runner 的多路复用构建根（docs/ui-revamp/ARCHITECTURE_PLAN.md §5.1、§5.4；
//! YIX_SPIKE.md V-1：模块根文件不能 import 自身目录之外的文件，所以构建根必须留在 src/ 根目录）。
//!
//! build.zig 为每个验收步骤注入具名模块 `root_select`（`name` = 产物名），这里在 comptime 选出
//! 实现文件并转发 std 与仓库代码会从根模块读取的声明。没被选中的分支只做语法解析，不做语义分析，
//! 其中用到的具名模块不要求在本次构建里存在。步骤名、产物名、链接配置不变。
//! `ai-gateway` 是测试二进制（test-ai-gateway）：测试模式下根模块是 test runner，这里只负责把实现文件
//! 拉进语义分析，使其 `test` 块进入二进制；`builtin-records-tests`、`compaction-e2e-tests`、`applog-tests` 同理。
const std = @import("std");
const name = @import("root_select").name;

fn is(comptime candidate: []const u8) bool {
    return comptime std.mem.eql(u8, name, candidate);
}

const Impl = if (is("vt-conformance-runner"))
    @import("vt/acceptance/vt_conformance_runner.zig")
else if (is("bmc-live-readonly"))
    @import("plugins/bmc_ikvm/acceptance/bmc_live_readonly_runner.zig")
else if (is("connection-transport-runner"))
    @import("host/acceptance/connection_transport_runner.zig")
else if (is("ssh-connection-wait-runner"))
    @import("proto/ssh/acceptance/ssh_connection_wait_runner.zig")
else if (is("ssh-hardening-runner"))
    @import("proto/ssh/acceptance/ssh_hardening_runner.zig")
else if (is("ssh-auth-loopback-runner"))
    @import("proto/ssh/acceptance/ssh_auth_loopback_runner.zig")
else if (is("ssh-exec-service-runner"))
    @import("proto/ssh/acceptance/ssh_exec_service_runner.zig")
else if (is("ssh-disconnect-runner"))
    @import("features/workspace/tests/acceptance/ssh_disconnect_runner.zig")
else if (is("ssh-bootstrap-runner"))
    @import("host/acceptance/ssh_bootstrap_runner.zig")
else if (is("ssh-shell-execution-runner"))
    @import("features/workspace/tests/acceptance/ssh_shell_execution_runner.zig")
else if (is("fixed-forward-runner"))
    @import("proto/ssh/acceptance/fixed_forward_runner.zig")
else if (is("socks-worker-host-runner"))
    @import("host/acceptance/socks_worker_host_runner.zig")
else if (is("forward-load-runner"))
    @import("proto/ssh/acceptance/forward_load_runner.zig")
else if (is("ssh-connection-details-runner"))
    @import("features/connections/wizard/tests/ssh_connection_details_runner.zig")
else if (is("ssh-reconnect-loopback-runner"))
    @import("features/workspace/tests/acceptance/ssh_reconnect_loopback_runner.zig")
else if (is("ssh-shared-connection-runner"))
    @import("features/workspace/tests/acceptance/ssh_shared_connection_runner.zig")
else if (is("application-environment-contract"))
    @import("platform/acceptance/application_environment_contract.zig")
else if (is("ai-gateway"))
    @import("ai/acceptance/ai_gateway_runner.zig")
else if (is("builtin-records-tests"))
    @import("features/terminal/tests/builtin_records_tests.zig")
else if (is("compaction-e2e-tests"))
    @import("ai/tests/compaction_e2e_tests.zig")
else if (is("applog-tests"))
    @import("platform/tests/applog_tests.zig")
else
    @compileError("src/acceptance.zig: unknown runner '" ++ name ++ "'");

// ── 根级声明转发（与 src/preview.zig 保持一致）───────────────────────
// 缺省值与“根文件没有该声明”时的行为相同：std.options 缺省为 `.{}`；
// platform/runtime_mode.zig 只在 `application_test_mode` 存在且为 true 时开启自动化。
pub const main = if (@hasDecl(Impl, "main")) Impl.main else @compileError("src/acceptance.zig: '" ++ name ++ "' has no main");
pub const std_options: std.Options = if (@hasDecl(Impl, "std_options")) Impl.std_options else .{};
pub const application_test_mode = if (@hasDecl(Impl, "application_test_mode")) Impl.application_test_mode else false;
/// 验收 runner 都是测试程序：缺省按测试构建隔离家目录（platform/user_dirs.zig）；
/// 只有代表正式 App 的 application-environment-contract 声明 false。
pub const zerowork_isolated_home = if (@hasDecl(Impl, "zerowork_isolated_home")) Impl.zerowork_isolated_home else true;

comptime {
    // 被选中的实现若声明了其他会被 std / zenit 从根模块读取的声明，必须在这里补转发，否则会被静默忽略。
    for ([_][]const u8{ "panic", "os", "debug", "tracy", "build_options", "zenit_web_glass", "std_options_debug_io", "std_options_debug_threaded_io", "std_options_cwd", "std_options_FilePermissions", "std_options_elf_debug_info_search_paths" }) |decl| {
        if (@hasDecl(Impl, decl)) @compileError("src/acceptance.zig: forward root declaration '" ++ decl ++ "' for '" ++ name ++ "'");
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
