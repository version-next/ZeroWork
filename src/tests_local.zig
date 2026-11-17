//! test-local 一组独立测试二进制的多路复用聚合根（docs/ui-revamp/ARCHITECTURE_PLAN.md §5.1、§5.4；
//! YIX_SPIKE.md V-1：模块根文件必须留在 src/ 根目录）。
//!
//! build.zig 为每个二进制注入具名模块 `root_select`（`name` = 运行文件名），这里只把被选中的测试文件
//! 拉进语义分析，使它的 `test` 块与顶层 `comptime` 块与原先作为根文件时相同。没被选中的分支只做语法解析。
const std = @import("std");
const name = @import("root_select").name;

fn is(comptime candidate: []const u8) bool {
    return comptime std.mem.eql(u8, name, candidate);
}

const Suite = if (is("local-process-tests"))
    @import("local/tests/local_process_tests.zig")
else if (is("terminal-controller-tests"))
    @import("vt/tests/terminal_controller_tests.zig")
else if (is("local-adapter-tests"))
    @import("local/tests/local_adapter_tests.zig")
else if (is("trusted-edit-tests"))
    @import("local/tests/local_trusted_edit_tests.zig")
else if (is("terminal-execution-tests"))
    @import("features/terminal/tests/terminal_execution_tests.zig")
else
    @compileError("src/tests_local.zig: unknown suite '" ++ name ++ "'");

comptime {
    _ = Suite;
}
