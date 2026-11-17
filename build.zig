const std = @import("std");
const zenit = @import("zenit");

pub fn build(b: *std.Build) void {
    // ZeroWork is intentionally macOS 13+ on Apple Silicon only (SPEC baseline).
    // Zig 0.17 build graph; the active Xcode SDK is selected by the toolchain.

    const target = b.resolveTargetQuery(.{
        .cpu_arch = .aarch64,
        .os_tag = .macos,
        .os_version_min = .{ .semver = .{
            .major = 13,
            .minor = 0,
            .patch = 0,
        } },
    });
    const optimize = b.standardOptimizeOption(.{});
    const verify_ssh = b.addSystemCommand(&.{ "python3", "scripts/verify_ssh_deps.py" });
    verify_ssh.setCwd(b.path("."));
    verify_ssh.has_side_effects = true;
    b.step("verify-ssh-deps", "Verify SSH source, configuration and archive provenance").dependOn(&verify_ssh.step);
    const test_mode = b.option(bool, "test-mode", "Enable the Zenit UI automation harness") orelse false;
    select_root_test_mode = test_mode;
    const plugin_fixture = b.option(bool, "plugin-fixture", "Link the non-terminal plugin acceptance fixture (test builds only)") orelse false;
    if (plugin_fixture and !test_mode) @panic("plugin-fixture requires -Dtest-mode=true; it must not enter production builds");
    const e2e_port = b.option(u16, "e2e-port", "Zenit Harness file-RPC directory suffix") orelse 19816;
    const zenit_dep = b.dependency("zenit", .{
        .target = target,
        .optimize = optimize,
        .@"test-mode" = test_mode,
        .@"e2e-port" = e2e_port,
    });
    // ZeroWork theme = zenit default design system + ZeroWork's own tokens
    // (src/shared/ui/theme/zerowork.tokens.json, e.g. zw_island_*). Layered at build
    // time, so zenit token updates flow through without copying its JSON.
    // Wired once on the dependency's shared `ui` module: every ZeroWork module
    // and test that imports `ui` sees the same provider.
    const zw_theme = zenit.generateThemeLayers(b, zenit_dep, &.{ zenit.defaultThemePath(zenit_dep), b.path("src/shared/ui/theme/zerowork.tokens.json") }, .{ .target = target, .optimize = optimize });
    zenit.wireThemeProvider(zenit_dep.module("ui"), zw_theme);

    const core = b.addModule("zerowork", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    // transfer_panel（root.zig 挂载）用 @import("ui")；纯 Zig 模块引用，
    // 不带 .m 源（.m 只经 attach/addNativeLibs 落到具体二进制）。
    core.addImport("ui", zenit_dep.module("ui"));
    core.addImport("icon_ir", zenit_dep.module("icon_ir"));
    // NOTE: core 不挂 "ui"——exe 已由 zenit.attach 挂载；重复挂载会让同一份
    // zenit .m 桥在 exe 链接里出现两份（duplicate symbol）。transfer_panel 的
    // 测试编译走 tests.root_module 的独立挂载（见 tests 段）。

    // Prebuilt libghostty-vt is produced by the official Ghostty Zig 0.17
    // branch and is the ONLY VT engine: ghostty_adapter.zig wraps its C ABI
    // behind the VtEngine contract (feed/resize/snapshot/lineAt/selection).
    core.addLibraryPath(b.path("vendor/libghostty-vt"));
    core.addIncludePath(b.path("vendor/libghostty-vt/include"));
    core.linkSystemLibrary("ghostty-vt", .{});
    core.linkSystemLibrary("curl", .{});

    const ghostty_translate = b.addTranslateC(.{ .root_source_file = b.path("vendor/libghostty-vt/include/ghostty/vt.h"), .target = target, .optimize = optimize });
    ghostty_translate.addIncludePath(b.path("vendor/libghostty-vt/include"));
    core.addImport("generated_ghostty_vt", ghostty_translate.createModule());
    // The static Local plugin owns the native PTY/process boundary.
    core.addCSourceFile(.{ .file = b.path("src/ai/mcp_native.c"), .flags = &.{"-std=c11"} });
    core.addCSourceFile(.{ .file = b.path("src/local/darwin_process.c"), .flags = &.{"-std=c11"} });
    core.addCSourceFile(.{ .file = b.path("src/platform/macos_credentials.m"), .flags = &.{} });
    core.addCSourceFile(.{ .file = b.path("src/platform/data_scope_lock.c"), .flags = &.{"-std=c11"} });
    core.linkFramework("Security", .{});
    core.linkFramework("CoreFoundation", .{});
    addUrlFetchFrameworks(core);
    addBmcNative(b, core);
    core.addCSourceFile(.{ .file = b.path("src/local/trusted_edit_native.c"), .flags = &.{"-std=c11"} });
    core.addCSourceFile(.{ .file = b.path("src/local/secret_native.c"), .flags = &.{"-std=c11"} });
    core.addSystemIncludePath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include" });
    core.addLibraryPath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/lib" });
    const ssh_channel_translate = b.addTranslateC(.{ .root_source_file = b.path("src/proto/ssh/libssh2_channel_shim.h"), .target = target, .optimize = optimize });
    ssh_channel_translate.addIncludePath(b.path("vendor/libssh2/include"));
    core.addImport("generated_ssh_channel", ssh_channel_translate.createModule());
    const ssh_session_translate = b.addTranslateC(.{ .root_source_file = b.path("src/proto/ssh/libssh2_session_shim.h"), .target = target, .optimize = optimize });
    ssh_session_translate.addIncludePath(b.path("vendor/libssh2/include"));
    core.addImport("generated_ssh_session", ssh_session_translate.createModule());

    // libssh2 and Mbed TLS are built as pinned static dependencies by the reproducible
    // scripts/build_ssh_deps.sh step; compile the stable ZeroWork shims here.
    core.addIncludePath(b.path("vendor/libssh2/include"));
    core.addIncludePath(b.path("vendor/mbedtls/include"));
    core.addIncludePath(b.path("src/proto/ssh"));
    core.addCSourceFiles(.{ .files = &.{
        "src/proto/ssh/libssh2_channel_shim.c",
        "src/proto/ssh/libssh2_session_shim.c",
    }, .flags = &.{"-std=c11"} });
    // The dependency script emits these archives; fail with a useful build error
    // instead of silently searching unrelated host libraries.
    core.addLibraryPath(b.path("vendor/libssh2/src/.libs"));
    core.addLibraryPath(b.path("vendor/mbedtls/library"));
    linkVendorSsh(b, core);
    core.linkSystemLibrary("z", .{});

    // VT conformance/perf runner: same engine as production (ghostty), driven
    // through the adapter-agnostic conformance_runner.zig harness.
    const vt_runner = b.addExecutable(.{
        .name = "vt-conformance-runner",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/acceptance.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "generated_ghostty_vt", .module = ghostty_translate.createModule() }},
        }),
    });
    selectRoot(b, vt_runner.root_module, "vt-conformance-runner");
    vt_runner.root_module.addLibraryPath(b.path("vendor/libghostty-vt"));
    vt_runner.root_module.addIncludePath(b.path("vendor/libghostty-vt/include"));
    vt_runner.root_module.linkSystemLibrary("ghostty-vt", .{});
    b.installArtifact(vt_runner);
    const vt_run = b.addRunArtifact(vt_runner);
    b.step("vt-perf", "Run deterministic VT conformance and performance samples").dependOn(&vt_run.step);

    // Yix/Yss sources (src/**/*.yix|.yss and tools/mockups/**) compile to
    // checked-in sibling twins with zenit's own compiler. gen-yix rewrites them;
    // check-yix fails on stale, orphaned or hand-edited twins and gates the
    // application build and every test binary that compiles the UI sources.
    const yix_dirs = [_][]const u8{ "src", "tools/mockups" };
    const yix_tool = zenit_dep.artifact("yix");
    const gen_yix = b.addRunArtifact(yix_tool);
    gen_yix.setCwd(b.path("."));
    gen_yix.addArg("gen");
    gen_yix.addArgs(&yix_dirs);
    gen_yix.has_side_effects = true;
    b.step("gen-yix", "Regenerate checked-in Yix/Yss twins under src and tools/mockups").dependOn(&gen_yix.step);
    const check_yix = b.addRunArtifact(yix_tool);
    check_yix.setCwd(b.path("."));
    check_yix.addArg("check");
    check_yix.addArgs(&yix_dirs);
    check_yix.has_side_effects = true;
    b.step("check-yix", "Fail when a Yix/Yss twin under src or tools/mockups is stale or hand-edited").dependOn(&check_yix.step);

    // Architecture guardrails (tools/arch, docs/ui-revamp/ARCHITECTURE_PLAN.md
    // §4.3/§6.3): import layering + test_id baselines. Host-only tool with no
    // zenit or repository module dependencies. Since P2 the application and all
    // test compile steps depend on it (check_arch_gate below).
    // Subcommands via -Darch-args, e.g. `zig build check-arch -Darch-args="imports --prune"`.
    const arch_tool = b.addExecutable(.{ .name = "check-arch", .root_module = b.createModule(.{
        .root_source_file = b.path("tools/arch/check_arch.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
    }) });
    const arch_tool_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("tools/arch/check_arch.zig"),
        .target = b.graph.host,
    }) });
    const run_arch_tool_tests = b.addRunArtifact(arch_tool_tests);
    b.step("test-arch", "Run the check-arch tool's own unit tests").dependOn(&run_arch_tool_tests.step);
    const check_arch = b.addRunArtifact(arch_tool);
    check_arch.setCwd(b.path("."));
    check_arch.has_side_effects = true;
    if (b.option([]const u8, "arch-args", "Space-separated arguments for check-arch (default: all)")) |arch_args| {
        var arch_arg_it = std.mem.tokenizeScalar(u8, arch_args, ' ');
        while (arch_arg_it.next()) |arg| check_arch.addArg(arg);
    }
    check_arch.step.dependOn(&run_arch_tool_tests.step);
    b.step("check-arch", "Check import layering and test_id baselines (tools/arch); runs test-arch first").dependOn(&check_arch.step);
    // P2 wiring (§4.3): the application and every test compile step depend on a
    // fixed-argument copy of the check (default `all`), next to check-yix, so a
    // new layering violation or a lost test_id fails the build. It is a separate
    // run so `-Darch-args` (e.g. `--update-baseline`) only affects the top-level
    // check-arch step. Cost when nothing changed: ~0.3 s (tool run) plus the cached
    // test-arch run.
    const check_arch_gate = b.addRunArtifact(arch_tool);
    check_arch_gate.setCwd(b.path("."));
    check_arch_gate.has_side_effects = true;
    check_arch_gate.step.dependOn(&run_arch_tool_tests.step);

    // One-off P1 relocation tool (tools/revamp, ARCHITECTURE_PLAN.md §6.2 P1; deleted in P6).
    // Host-only, no zenit or repository module dependencies; cwd is the repository root.
    // e.g. `zig build relocate -Drelocate-args="--package shared-ui --dry-run --report /abs/refs.tsv"`.
    const relocate_tool = b.addExecutable(.{ .name = "relocate", .root_module = b.createModule(.{
        .root_source_file = b.path("tools/revamp/relocate.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
    }) });
    const relocate_tool_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("tools/revamp/relocate.zig"),
        .target = b.graph.host,
    }) });
    const run_relocate_tool_tests = b.addRunArtifact(relocate_tool_tests);
    b.step("test-relocate", "Run the one-off relocate tool's own unit tests").dependOn(&run_relocate_tool_tests.step);
    const relocate = b.addRunArtifact(relocate_tool);
    relocate.setCwd(b.path("."));
    relocate.has_side_effects = true;
    if (b.option([]const u8, "relocate-args", "Space-separated arguments for relocate (--package NAME | --all, --dry-run, --report PATH)")) |relocate_args| {
        var relocate_arg_it = std.mem.tokenizeScalar(u8, relocate_args, ' ');
        while (relocate_arg_it.next()) |arg| relocate.addArg(arg);
    }
    relocate.step.dependOn(&run_relocate_tool_tests.step);
    b.step("relocate", "Move files per docs/ui-revamp/move-map/_final.tsv and rewrite relative paths (tools/revamp); runs test-relocate first").dependOn(&relocate.step);

    const exe = b.addExecutable(.{
        .name = "zerowork",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zerowork", .module = core }},
        }),
    });
    exe.step.dependOn(&verify_ssh.step);
    exe.step.dependOn(&check_yix.step);
    exe.step.dependOn(&check_arch_gate.step);
    const application_options = b.addOptions();
    application_options.addOption(bool, "plugin_fixture", plugin_fixture);
    application_options.addOption(bool, "test_mode", test_mode);
    const git_commit = buildCommand(b, &.{ "git", "rev-parse", "--short=12", "HEAD" }) orelse "未知";
    const git_branch = buildCommand(b, &.{ "git", "rev-parse", "--abbrev-ref", "HEAD" }) orelse "未知";
    const git_status = buildCommand(b, &.{ "git", "status", "--porcelain", "--untracked-files=normal" });
    const build_time = buildCommand(b, &.{ "date", "+%Y-%m-%d %H:%M:%S %z" }) orelse "未知";
    application_options.addOption([]const u8, "version_metadata", b.fmt("{s}@{s}{s} · {s}", .{
        if (std.mem.eql(u8, git_branch, "HEAD")) "HEAD" else git_branch,
        git_commit,
        if (git_status) |status| (if (status.len != 0) "*" else "") else "?",
        build_time,
    }));
    exe.root_module.addOptions("application_options", application_options);

    // Zenit owns the native macOS window/input/Metal boundary. ZeroWork adds no separate UI bridge.
    exe.root_module.addImport("generated_ghostty_vt", ghostty_translate.createModule());
    exe.root_module.addImport("generated_ssh_channel", ssh_channel_translate.createModule());
    exe.root_module.addImport("generated_ssh_session", ssh_session_translate.createModule());

    zenit.attach(zenit_dep, exe);
    exe.root_module.addCSourceFile(.{ .file = b.path("src/platform/macos_notifications.m"), .flags = &.{"-fobjc-arc"} });
    exe.root_module.linkFramework("UserNotifications", .{});
    exe.root_module.addCSourceFile(.{ .file = b.path("src/platform/macos_data_alert.m"), .flags = &.{"-fobjc-arc"} });
    exe.root_module.addCSourceFile(.{ .file = b.path("src/platform/macos_password_reveal.m"), .flags = &.{"-fobjc-arc"} });
    exe.root_module.addCSourceFile(.{ .file = b.path("src/platform/macos_transfer_picker.m"), .flags = &.{"-fobjc-arc"} });
    exe.root_module.addCSourceFile(.{ .file = b.path("src/platform/macos_background_picker.m"), .flags = &.{"-fobjc-arc"} });
    exe.root_module.addCSourceFile(.{ .file = b.path("src/platform/macos_skill_picker.m"), .flags = &.{"-fobjc-arc"} });
    exe.root_module.addCSourceFile(.{ .file = b.path("src/platform/app_icon.m"), .flags = &.{"-fobjc-arc"} });
    exe.root_module.addCSourceFile(.{ .file = b.path("src/platform/macos_app_menu.m"), .flags = &.{"-fobjc-arc"} });
    exe.root_module.addCSourceFile(.{ .file = b.path("src/platform/macos_menu_bar.m"), .flags = if (test_mode) &.{ "-fobjc-arc", "-DZW_MENU_BAR_TEST=1" } else &.{"-fobjc-arc"} });
    exe.root_module.addAnonymousImport("app_icon_assets", .{ .root_source_file = b.path("assets/macos/icons.zig") });
    exe.root_module.addAnonymousImport("ui_font_assets", .{ .root_source_file = b.path("assets/fonts/native.zig") });
    exe.root_module.addCSourceFile(.{ .file = b.path("src/platform/ui_fonts.m"), .flags = &.{} });
    exe.root_module.addCSourceFile(.{ .file = b.path("src/platform/macos_file_promises.m"), .flags = &.{"-fobjc-arc"} });
    // zenit public native headers (pre-routing event filter used by the secret panel).
    exe.root_module.addIncludePath(zenit_dep.path("native/macos"));
    exe.root_module.addCSourceFile(.{ .file = b.path("src/platform/macos_host_secret.m"), .flags = &.{"-fobjc-arc"} });
    exe.root_module.linkFramework("Carbon", .{});
    exe.root_module.addImport("icon_ir", zenit_dep.module("icon_ir"));
    zenit.installHarnessClient(b, zenit_dep);
    exe.root_module.addSystemFrameworkPath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks" });
    exe.root_module.addSystemIncludePath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include" });
    exe.root_module.addLibraryPath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/lib" });

    exe.root_module.addCSourceFiles(.{ .files = &.{ "src/update/native_shared.m", "src/update/native_runtime.m" }, .flags = if (test_mode) &.{ "-fobjc-arc", "-Wno-deprecated-declarations", "-DZW_UPDATE_TESTING=1" } else &.{ "-fobjc-arc", "-Wno-deprecated-declarations" } });
    exe.root_module.linkFramework("Security", .{});
    exe.root_module.linkFramework("LocalAuthentication", .{});
    exe.root_module.linkSystemLibrary("archive", .{});
    // Test builds use a separate helper root that links platform/user_dirs
    // (the module roots under src/update reach it through a named module);
    // the formal helper root and binary are unchanged.
    const updater = b.addExecutable(.{ .name = "ZeroWorkUpdater", .root_module = b.createModule(.{ .root_source_file = b.path(if (test_mode) "src/update/helper_test_main.zig" else "src/update/helper_main.zig"), .target = target, .optimize = optimize }) });
    const user_dirs_native = b.createModule(.{ .root_source_file = b.path("src/platform/user_dirs_native.zig"), .target = target, .optimize = optimize, .link_libc = true });
    if (test_mode) updater.root_module.addImport("user_dirs_native", user_dirs_native);
    updater.root_module.addCSourceFiles(.{ .files = &.{ "src/update/native_shared.m", "src/update/native_installer.m" }, .flags = if (test_mode) &.{ "-fobjc-arc", "-Wno-deprecated-declarations", "-DZW_UPDATE_TESTING=1" } else &.{ "-fobjc-arc", "-Wno-deprecated-declarations" } });
    updater.root_module.link_libc = true;
    updater.root_module.linkFramework("AppKit", .{});
    updater.root_module.linkFramework("Foundation", .{});
    updater.root_module.linkFramework("Security", .{});
    updater.root_module.linkSystemLibrary("archive", .{});
    updater.root_module.addSystemFrameworkPath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks" });
    updater.root_module.addSystemIncludePath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include" });
    updater.root_module.addLibraryPath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/lib" });
    // Shared inputs for the standalone test roots built by addStandaloneTest().
    const standalone = StandaloneTestContext{
        .b = b,
        .target = target,
        .optimize = optimize,
        .zenit_dep = zenit_dep,
        .ghostty_translate = ghostty_translate,
        .ssh_session_translate = ssh_session_translate,
        .ssh_channel_translate = ssh_channel_translate,
        .verify_ssh = &verify_ssh.step,
        .check_yix = &check_yix.step,
        .check_arch_gate = &check_arch_gate.step,
    };
    const update_tests = addStandaloneTest(standalone, .update, .{ .filters = &.{ "update ", "settings page map" } });
    b.step("test-update", "Run updater state and config contracts").dependOn(&b.addRunArtifact(update_tests).step);
    const update_tools = b.step("build-update-tools", "Build isolated updater tools");
    update_tools.dependOn(&b.addInstallArtifact(updater, .{}).step);
    if (test_mode) {
        const fixture = b.addExecutable(.{ .name = "update-fixture", .root_module = b.createModule(.{ .root_source_file = b.path("src/update/fixture_main.zig"), .target = target, .optimize = optimize }) });
        fixture.root_module.addImport("user_dirs_native", user_dirs_native);
        fixture.root_module.addCSourceFiles(.{ .files = &.{ "src/update/native_shared.m", "src/update/native_runtime.m", "src/update/native_fixture.m" }, .flags = &.{ "-fobjc-arc", "-Wno-deprecated-declarations", "-DZW_UPDATE_TESTING=1" } });
        fixture.root_module.link_libc = true;
        fixture.root_module.linkFramework("AppKit", .{});
        fixture.root_module.linkFramework("Foundation", .{});
        fixture.root_module.linkFramework("Security", .{});
        fixture.root_module.linkSystemLibrary("archive", .{});
        fixture.root_module.addSystemFrameworkPath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks" });
        fixture.root_module.addSystemIncludePath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include" });
        fixture.root_module.addLibraryPath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/lib" });
        update_tools.dependOn(&b.addInstallArtifact(fixture, .{}).step);
        b.installArtifact(fixture);
    }
    b.installArtifact(updater);
    b.installArtifact(exe);
    // 测试专用入口（系统文件对话框注入器等）只在 -Dtest-mode=true 时编译进 zerowork。
    // 每次安装都用刚链接出的二进制做只读字节扫描：正式构建里不得出现任何痕迹；
    // test-mode 构建里必须能看到（正向对照，证明检查没有因改名 / 剥符号而失效）。
    const hooks_tool = b.addExecutable(.{ .name = "check-test-hooks", .root_module = b.createModule(.{
        .root_source_file = b.path("tools/binary_guard/check_test_hooks.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
    }) });
    const hooks_tool_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("tools/binary_guard/check_test_hooks.zig"),
        .target = b.graph.host,
    }) });
    const check_test_hooks = b.addRunArtifact(hooks_tool);
    check_test_hooks.addFileArg(exe.getEmittedBin());
    check_test_hooks.addArg(if (test_mode) "test-mode" else "formal");
    check_test_hooks.step.dependOn(&b.addRunArtifact(hooks_tool_tests).step);
    b.step("check-test-hooks", "Scan the linked zerowork binary: test-only hooks absent in formal builds, present in -Dtest-mode=true").dependOn(&check_test_hooks.step);
    b.getInstallStep().dependOn(&check_test_hooks.step);
    // libssh2 / Mbed TLS 只能静态链接 vendor 归档（linkVendorSsh）；正式与 test-mode 构建
    // 安装时都核对链接产物，防止再经 pkg-config 链到主机的 Mbed TLS（REQUESTS #54）。
    const ssh_link_tool = b.addExecutable(.{ .name = "check-ssh-link", .root_module = b.createModule(.{
        .root_source_file = b.path("tools/binary_guard/check_ssh_link.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
    }) });
    const ssh_link_tool_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("tools/binary_guard/check_ssh_link.zig"),
        .target = b.graph.host,
    }) });
    const check_ssh_link = b.addRunArtifact(ssh_link_tool);
    check_ssh_link.addFileArg(exe.getEmittedBin());
    check_ssh_link.step.dependOn(&b.addRunArtifact(ssh_link_tool_tests).step);
    b.step("check-ssh-link", "Scan the linked zerowork binary: libssh2 / Mbed TLS only from the static vendor archives").dependOn(&check_ssh_link.step);
    b.getInstallStep().dependOn(&check_ssh_link.step);
    // The local ZSH edit bridge is loaded only by this process's private
    // bootstrap, from beside the executable in both CLI and app bundles.
    const zsh_bridge = b.addSystemCommand(&.{ "xcrun", "clang", "-target", "arm64-apple-macos13.0", "-bundle", "-undefined", "dynamic_lookup", "-O2" });
    zsh_bridge.addFileArg(b.path("src/local/shell/zw_ipc.c"));
    zsh_bridge.addArg("-o");
    const zsh_bridge_file = zsh_bridge.addOutputFileArg("zw_ipc.so");
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(zsh_bridge_file, .bin, "zw_ipc.so").step);
    const execution_bridge = b.addSystemCommand(&.{ "xcrun", "clang", "-target", "arm64-apple-macos13.0", "-bundle", "-undefined", "dynamic_lookup", "-O2", "-DZW_EXECUTION=1" });
    execution_bridge.addFileArg(b.path("src/local/shell/zw_ipc.c"));
    execution_bridge.addArg("-o");
    const execution_bridge_file = execution_bridge.addOutputFileArg("zw_execution.so");
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(execution_bridge_file, .bin, "zw_execution.so").step);
    const secret_consumer = b.addSystemCommand(&.{ "xcrun", "clang", "-target", "arm64-apple-macos13.0", "-bundle", "-undefined", "dynamic_lookup", "-std=c11", "-O2" });
    secret_consumer.addFileArg(b.path("src/local/shell/secret_consume.c"));
    secret_consumer.addArg("-o");
    const secret_consumer_file = secret_consumer.addOutputFileArg("zw_secret_consume.so");
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(secret_consumer_file, .bin, "zw_secret_consume.so").step);
    const execution_guard = b.addSystemCommand(&.{ "xcrun", "clang", "-target", "arm64-apple-macos13.0", "-std=c11", "-Wall", "-Wextra", "-Werror", "-O2" });
    execution_guard.addFileArg(b.path("src/local/shell/execution_guard.c"));
    execution_guard.addArg("-o");
    const execution_guard_file = execution_guard.addOutputFileArg("zw_execution_guard");
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(execution_guard_file, .bin, "zw_execution_guard").step);
    // Versioned remote resources are bundled, never fetched by a target host.
    // Building Linux candidates does not grant runtime compatibility/ready.
    const ssh_bootstrap = b.addSystemCommand(&.{ "python3", "scripts/build_ssh_bootstrap.py", "--output" });
    const ssh_bootstrap_directory = ssh_bootstrap.addOutputDirectoryArg("ssh-bootstrap-v1");
    for ([_][]const u8{ "scripts/build_ssh_bootstrap.py", "src/proto/ssh/bootstrap/v1/launcher.c", "src/proto/ssh/bootstrap/v1/zw_ssh_execution.c", "src/proto/ssh/bootstrap/v1/execution.zsh" }) |source| ssh_bootstrap.addFileInput(b.path(source));
    const install_ssh_bootstrap = b.addInstallDirectory(.{ .source_dir = ssh_bootstrap_directory, .install_dir = .prefix, .install_subdir = "share/zerowork/ssh-bootstrap/v1" });
    b.getInstallStep().dependOn(&install_ssh_bootstrap.step);
    b.step("ssh-bootstrap-resources", "Build hash-manifested BootstrapV1 remote candidates without deployment").dependOn(&install_ssh_bootstrap.step);

    // ── Mockup 预览（设计稿实机比对基建） ───────────────────────────
    // Build only the selected native design preview, outside production sources.
    const mockup_name = b.option([]const u8, "mockup", "Mockup preview name (docs/SPEC/html/mockup-<name>.html)") orelse "";
    if (mockup_name.len > 0) {
        // 视图文件名 = mockup 名（'-'→'_'，与 stub 生成规则一致）。
        const file_zig_name = b.allocator.dupe(u8, mockup_name) catch @panic("OOM");
        for (file_zig_name) |*c| {
            if (c.* == '-') c.* = '_';
        }
        const view_path = b.fmt("tools/mockups/{s}.zig", .{file_zig_name});
        // 隔离关键：视图文件由 build 层装配为独立模块 —— 每次构建的
        // import 图只包含被选中的这一个 mockup，其他子智能体文件的
        // 语法错误不会波及本次构建（Zig @import 是 AstGen 急切解析，
        // mockup_main 内的 comptime if 剪枝挡不住）。
        const view_module = b.createModule(.{
            .root_source_file = b.path(view_path),
            .target = target,
            .optimize = optimize,
        });
        view_module.addImport("ui", zenit_dep.module("ui"));
        const design_tokens = b.createModule(.{
            .root_source_file = b.path("src/shared/ui/theme/design_tokens.zig"),
            .target = target,
            .optimize = optimize,
        });
        design_tokens.addImport("ui", zenit_dep.module("ui"));
        view_module.addImport("design_tokens", design_tokens);
        const mockup_options = b.addOptions();
        mockup_options.addOption([]const u8, "mockup", mockup_name);
        mockup_options.addOption(bool, "test_mode", test_mode);
        const mockup_exe = b.addExecutable(.{
            .name = b.fmt("mockup-{s}", .{mockup_name}),
            .root_module = b.createModule(.{
                .root_source_file = b.path("tools/mockups/runner.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        mockup_exe.root_module.addOptions("build_options", mockup_options);
        mockup_exe.root_module.addImport("mockup_view", view_module);
        // Mockup 预览不链接 ghostty/libssh2（纯 UI 复刻，构建更快、依赖更少）。
        zenit.attach(zenit_dep, mockup_exe);
        mockup_exe.root_module.addSystemFrameworkPath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks" });
        mockup_exe.root_module.addSystemIncludePath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include" });
        mockup_exe.root_module.addLibraryPath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/lib" });
        // 专用 install step：`zig build mockup -Dmockup=<name>` 只构建预览程序，
        // 不触发主程序构建（否则并行开发时互相拖慢）。
        const mockup_step = b.step("mockup", "Build one design-mockup preview executable (-Dmockup=<name>)");
        mockup_step.dependOn(&b.addInstallArtifact(mockup_exe, .{}).step);
    }

    // Explicit component acceptance only; never part of the default install.
    // This mounts production SettingsController/content without the app shell.
    const settings_preview = b.addExecutable(.{
        .name = "settings-preview-runner",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/preview.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    selectRoot(b, settings_preview.root_module, "settings-preview-runner");
    zenit.attach(zenit_dep, settings_preview);
    settings_preview.root_module.addImport("icon_ir", zenit_dep.module("icon_ir"));
    settings_preview.root_module.addSystemFrameworkPath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks" });
    settings_preview.root_module.addSystemIncludePath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include" });
    settings_preview.root_module.addLibraryPath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/lib" });
    b.step("settings-preview", "Build the read-only planning component acceptance runner").dependOn(&b.addInstallArtifact(settings_preview, .{}).step);

    if (test_mode) {
        const files_preview = b.addExecutable(.{ .name = "file-workspace-preview", .root_module = b.createModule(.{ .root_source_file = b.path("src/preview.zig"), .target = target, .optimize = optimize }) });
        selectRoot(b, files_preview.root_module, "file-workspace-preview");
        zenit.attach(zenit_dep, files_preview);
        files_preview.root_module.addSystemFrameworkPath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks" });
        files_preview.root_module.addSystemIncludePath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include" });
        files_preview.root_module.addLibraryPath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/lib" });
        files_preview.root_module.addImport("icon_ir", zenit_dep.module("icon_ir"));
        b.step("file-workspace-preview", "Build the production file component for isolated theme acceptance").dependOn(&b.addInstallArtifact(files_preview, .{}).step);
    }

    // Retained legacy authentication component acceptance; never installed by default.
    const auth_preview = b.addExecutable(.{ .name = "auth-challenge-preview", .root_module = b.createModule(.{ .root_source_file = b.path("src/preview.zig"), .target = target, .optimize = optimize }) });
    selectRoot(b, auth_preview.root_module, "auth-challenge-preview");
    zenit.attach(zenit_dep, auth_preview);
    auth_preview.root_module.addSystemFrameworkPath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks" });
    auth_preview.root_module.addSystemIncludePath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include" });
    auth_preview.root_module.addLibraryPath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/lib" });
    auth_preview.root_module.addImport("icon_ir", zenit_dep.module("icon_ir"));
    b.step("auth-challenge-preview", "Build isolated retained authentication component acceptance window").dependOn(&b.addInstallArtifact(auth_preview, .{}).step);

    const connection_progress_preview = b.addExecutable(.{ .name = "connection-progress-preview", .root_module = b.createModule(.{ .root_source_file = b.path("src/preview.zig"), .target = target, .optimize = optimize }) });
    selectRoot(b, connection_progress_preview.root_module, "connection-progress-preview");
    zenit.attach(zenit_dep, connection_progress_preview);
    connection_progress_preview.root_module.addImport("generated_ssh_session", ssh_session_translate.createModule());
    connection_progress_preview.root_module.addImport("generated_ssh_channel", ssh_channel_translate.createModule());
    connection_progress_preview.root_module.addSystemFrameworkPath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks" });
    connection_progress_preview.root_module.addSystemIncludePath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include" });
    connection_progress_preview.root_module.addLibraryPath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/lib" });
    b.step("connection-progress-preview", "Build isolated production connection progress view").dependOn(&b.addInstallArtifact(connection_progress_preview, .{}).step);

    const events_preview = b.addExecutable(.{ .name = "transfer-events-preview", .root_module = b.createModule(.{ .root_source_file = b.path("src/preview.zig"), .target = target, .optimize = optimize }) });
    selectRoot(b, events_preview.root_module, "transfer-events-preview");
    zenit.attach(zenit_dep, events_preview);
    events_preview.root_module.addSystemFrameworkPath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks" });
    events_preview.root_module.addSystemIncludePath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include" });
    events_preview.root_module.addLibraryPath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/lib" });
    events_preview.root_module.addImport("icon_ir", zenit_dep.module("icon_ir"));
    b.step("transfer-events-preview", "Build isolated native transfer event acceptance fixture").dependOn(&b.addInstallArtifact(events_preview, .{}).step);

    const conflict_preview = b.addExecutable(.{ .name = "transfer-conflict-preview", .root_module = b.createModule(.{ .root_source_file = b.path("src/preview.zig"), .target = target, .optimize = optimize }) });
    selectRoot(b, conflict_preview.root_module, "transfer-conflict-preview");
    zenit.attach(zenit_dep, conflict_preview);
    conflict_preview.root_module.addSystemFrameworkPath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks" });
    conflict_preview.root_module.addSystemIncludePath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include" });
    conflict_preview.root_module.addLibraryPath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/lib" });
    conflict_preview.root_module.addImport("icon_ir", zenit_dep.module("icon_ir"));
    b.step("transfer-conflict-preview", "Build isolated native transfer conflict acceptance fixture").dependOn(&b.addInstallArtifact(conflict_preview, .{}).step);

    const transfer_controls_preview = b.addExecutable(.{ .name = "transfer-controls-preview", .root_module = b.createModule(.{ .root_source_file = b.path("src/preview.zig"), .target = target, .optimize = optimize }) });
    selectRoot(b, transfer_controls_preview.root_module, "transfer-controls-preview");
    const transfer_controls_options = b.addOptions();
    transfer_controls_options.addOption([]const u8, "presentation", b.option([]const u8, "transfer-preview-presentation", "global_popover, session_popover or session_tray") orelse "global_popover");
    transfer_controls_preview.root_module.addOptions("preview_options", transfer_controls_options);
    zenit.attach(zenit_dep, transfer_controls_preview);
    transfer_controls_preview.root_module.addSystemFrameworkPath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks" });
    transfer_controls_preview.root_module.addSystemIncludePath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include" });
    transfer_controls_preview.root_module.addLibraryPath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/lib" });
    transfer_controls_preview.root_module.addImport("icon_ir", zenit_dep.module("icon_ir"));
    b.step("transfer-controls-preview", "Build shared Figma transfer cards and close-control acceptance fixture").dependOn(&b.addInstallArtifact(transfer_controls_preview, .{}).step);

    // SOCKS information card (features/connections/socks/view/socks_info_view.zig) in a fixture window: pure UI with
    // fabricated listener facts; links no SSH / network code and keeps no on-disk state.
    const socks_info_preview = b.addExecutable(.{ .name = "socks-info-preview", .root_module = b.createModule(.{ .root_source_file = b.path("src/preview.zig"), .target = target, .optimize = optimize }) });
    selectRoot(b, socks_info_preview.root_module, "socks-info-preview");
    zenit.attach(zenit_dep, socks_info_preview);
    socks_info_preview.root_module.addSystemFrameworkPath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks" });
    socks_info_preview.root_module.addSystemIncludePath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include" });
    socks_info_preview.root_module.addLibraryPath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/lib" });
    socks_info_preview.root_module.addImport("icon_ir", zenit_dep.module("icon_ir"));
    b.step("socks-info-preview", "Build isolated SOCKS information card acceptance fixture").dependOn(&b.addInstallArtifact(socks_info_preview, .{}).step);

    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    b.step("run", "Run the ZeroWork bootstrap").dependOn(&run.step);

    const root_test_filter = b.option([]const u8, "test-filter", "Run only matching unit and contract tests");
    const tests = b.addTest(.{ .filters = if (root_test_filter) |filter| &.{filter} else &.{}, .root_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    // A separate module keeps native test bridges out of the production
    // module, while collecting every root.zig test in this test binary.
    tests.root_module.addImport("ui", zenit_dep.module("ui"));
    tests.root_module.addImport("zenit_app", zenit_dep.module("zenit_app"));
    tests.root_module.addImport("icon_ir", zenit_dep.module("icon_ir"));
    // Production terminal event tests instantiate the real input path without
    // opening an SSH connection. Supply the same native ABI as the app.
    tests.root_module.addImport("generated_ghostty_vt", ghostty_translate.createModule());
    tests.root_module.addImport("generated_ssh_session", ssh_session_translate.createModule());
    tests.root_module.addImport("generated_ssh_channel", ssh_channel_translate.createModule());
    tests.root_module.addLibraryPath(b.path("vendor/libghostty-vt"));
    tests.root_module.linkSystemLibrary("ghostty-vt", .{});
    tests.root_module.linkSystemLibrary("curl", .{});
    tests.root_module.addIncludePath(b.path("vendor/libssh2/include"));
    tests.root_module.addIncludePath(b.path("vendor/mbedtls/include"));
    tests.root_module.addIncludePath(b.path("src/proto/ssh"));
    tests.root_module.addCSourceFiles(.{ .files = &.{ "src/proto/ssh/libssh2_channel_shim.c", "src/proto/ssh/libssh2_session_shim.c", "src/local/darwin_process.c", "src/ai/mcp_native.c", "src/local/trusted_edit_native.c", "src/local/secret_native.c" }, .flags = &.{"-std=c11"} });
    tests.root_module.addCSourceFile(.{ .file = b.path("src/platform/data_scope_lock.c"), .flags = &.{"-std=c11"} });
    // Keeps the exec environ array Zig's test runner holds intact across setenv / unsetenv in tests.
    tests.root_module.addCSourceFile(.{ .file = b.path("src/shared/testing/environ_detach.c"), .flags = &.{"-std=c11"} });
    tests.root_module.addLibraryPath(b.path("vendor/libssh2/src/.libs"));
    tests.root_module.addLibraryPath(b.path("vendor/mbedtls/library"));
    linkVendorSsh(b, tests.root_module);
    tests.step.dependOn(&verify_ssh.step);
    tests.step.dependOn(&check_yix.step);
    tests.step.dependOn(&check_arch_gate.step);
    tests.root_module.linkSystemLibrary("z", .{});
    addUrlFetchFrameworks(tests.root_module);

    addCoreTextBridgeForTest(zenit_dep, tests);
    addBmcNative(b, tests.root_module);
    tests.root_module.addCSourceFile(.{ .file = zenit_dep.path("native/macos/metal_bridge.m"), .flags = &.{"-fobjc-arc"} });
    tests.root_module.linkFramework("Metal", .{});
    tests.root_module.linkFramework("QuartzCore", .{});
    // fetch_url 的真实联网验收（经系统代理访问公网）：常规 test / test-ui / test-* 里 SkipZigTest，
    // 只有这个显式步骤设置 ZEROWORK_FETCH_NETWORK_LIVE=1 并运行它（不进任何门禁）。
    const fetch_network_tests = b.addTest(.{ .name = "fetch-network-tests", .filters = &.{"fetch_url std.http production route"}, .root_module = tests.root_module });
    const run_fetch_network_tests = b.addRunArtifact(fetch_network_tests);
    run_fetch_network_tests.setEnvironmentVariable("ZEROWORK_FETCH_NETWORK_LIVE", "1");
    run_fetch_network_tests.has_side_effects = true;
    b.step("test-fetch-network", "Opt-in: fetch_url production route through the configured system proxy to a real public URL (needs network)").dependOn(&run_fetch_network_tests.step);
    const bmc_tests = addStandaloneTest(standalone, .bmc, .{ .filters = if (root_test_filter) |filter| &.{filter} else &.{"BMC "} });
    b.step("test-bmc", "Run isolated V0.3 public seams, protocol and UI contract tests").dependOn(&b.addRunArtifact(bmc_tests).step);

    const root_test_step = b.step("test", "Run unit and contract tests");
    const root_test_files = b.addWriteFiles();
    const root_test_binary = root_test_files.addCopyFile(tests.getEmittedBin(), "unit-tests");
    _ = root_test_files.addCopyFile(zsh_bridge_file, "zw_ipc.so");
    _ = root_test_files.addCopyFile(execution_bridge_file, "zw_execution.so");
    _ = root_test_files.addCopyFile(secret_consumer_file, "zw_secret_consume.so");
    _ = root_test_files.addCopyFile(execution_guard_file, "zw_execution_guard");
    const root_test_run = std.Build.Step.Run.create(b, "run unit and contract tests");
    root_test_run.addFileArg(root_test_binary);
    root_test_step.dependOn(&root_test_run.step);
    const check_test_ssh_link = b.addRunArtifact(ssh_link_tool);
    check_test_ssh_link.addFileArg(root_test_binary);
    root_test_step.dependOn(&check_test_ssh_link.step);
    // Every Security entry point is mocked: this regression cannot access a
    // user's Keychain or display authentication UI.
    const native_credentials = b.addSystemCommand(&.{ "xcrun", "clang", "-Wall", "-Wextra", "-Werror" });
    native_credentials.addFileArg(b.path("src/platform/macos_credentials_tests.m"));
    native_credentials.addArgs(&.{ "-framework", "Security", "-framework", "CoreFoundation", "-o" });
    const native_credentials_binary = native_credentials.addOutputFileArg("credentials-native-mock");
    const native_credentials_run = std.Build.Step.Run.create(b, "credentials-native-mock");
    native_credentials_run.addFileArg(native_credentials_binary);
    root_test_step.dependOn(&native_credentials_run.step);
    b.step("test-credentials-native", "Run credential cache and no-UI regressions with mocked Security APIs").dependOn(&native_credentials_run.step);
    const reveal_native = b.addSystemCommand(&.{ "xcrun", "clang", "-fobjc-arc", "-Wall", "-Wextra", "-Werror", "-Wno-unused-parameter" });
    reveal_native.addFileArg(b.path("src/platform/macos_password_reveal_tests.m"));
    reveal_native.addFileInput(b.path("src/platform/macos_password_reveal.m"));
    reveal_native.addArgs(&.{ "-framework", "Foundation", "-framework", "LocalAuthentication", "-o" });
    const reveal_native_binary = reveal_native.addOutputFileArg("password-reveal-native-mock");
    const reveal_native_run = std.Build.Step.Run.create(b, "password-reveal-native-mock");
    reveal_native_run.addFileArg(reveal_native_binary);
    root_test_step.dependOn(&reveal_native_run.step);
    b.step("test-password-reveal-native", "Run password reveal authorization regressions without real authentication").dependOn(&reveal_native_run.step);
    const secret_transport = b.addSystemCommand(&.{ "xcrun", "clang", "-target", "arm64-apple-macos13.0", "-std=c11", "-Wall", "-Wextra", "-Werror" });
    secret_transport.addFileArg(b.path("src/local/secret_native.c"));
    secret_transport.addFileArg(b.path("src/local/secret_native_tests.c"));
    secret_transport.addArg("-o");
    const secret_transport_binary = secret_transport.addOutputFileArg("secret-native-transport-tests");
    const secret_transport_run = std.Build.Step.Run.create(b, "secret-native-transport-tests");
    secret_transport_run.addFileArg(secret_transport_binary);
    b.step("test-secret-transport", "Run isolated fresh-connection secret transport and child-PID rejection tests").dependOn(&secret_transport_run.step);

    // Real child processes exercise runtime flock ownership without launching
    // ZeroWork, touching application data, or calling Security APIs.
    const scope_native = b.addSystemCommand(&.{ "xcrun", "clang", "-std=c11", "-Wall", "-Wextra", "-Werror" });
    scope_native.addFileArg(b.path("src/platform/data_scope_lock_tests.c"));
    scope_native.addArgs(&.{ "-framework", "CoreFoundation", "-o" });
    const scope_native_binary = scope_native.addOutputFileArg("data-scope-lock-tests");
    const scope_native_run = std.Build.Step.Run.create(b, "data-scope-lock-tests");
    scope_native_run.addFileArg(scope_native_binary);
    root_test_step.dependOn(&scope_native_run.step);
    b.step("test-data-scope-lock", "Run real-process data scope lock and crash recovery regressions").dependOn(&scope_native_run.step);

    // Local process/VT integration stays headless and uses isolated test data.
    const local_tests_step = b.step("test-local", "Run real local PTY, terminal controller and adapter tests");
    // Mock only the OS observation boundary to force exit/ownership races.
    const close_observation = b.addSystemCommand(&.{ "xcrun", "clang", "-std=c11", "-Wall", "-Wextra", "-Werror" });
    close_observation.addFileArg(b.path("src/local/darwin_process_tests.c"));
    close_observation.addFileInput(b.path("src/local/darwin_process.c"));
    close_observation.addFileInput(b.path("src/local/darwin_process.h"));
    close_observation.addArg("-o");
    const close_observation_binary = close_observation.addOutputFileArg("local-close-observation-tests");
    const close_observation_run = std.Build.Step.Run.create(b, "local-close-observation-tests");
    close_observation_run.addFileArg(close_observation_binary);
    local_tests_step.dependOn(&close_observation_run.step);
    b.step("test-local-close-observation", "Run deterministic Local cleanup ownership and exit races").dependOn(&close_observation_run.step);
    const local_test_filter = b.option([]const u8, "local-test-filter", "Run only matching local terminal tests");
    for ([_][]const u8{ "local-process-tests", "terminal-controller-tests", "local-adapter-tests", "trusted-edit-tests", "terminal-execution-tests" }) |suite| {
        const local_tests = b.addTest(.{ .filters = if (local_test_filter) |filter| &.{filter} else &.{}, .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests_local.zig"),
            .target = target,
            .optimize = optimize,
        }) });
        selectRoot(b, local_tests.root_module, suite);
        local_tests.root_module.addImport("generated_ghostty_vt", ghostty_translate.createModule());
        local_tests.root_module.addLibraryPath(b.path("vendor/libghostty-vt"));
        local_tests.root_module.linkSystemLibrary("ghostty-vt", .{});
        local_tests.root_module.addCSourceFile(.{ .file = b.path("src/local/darwin_process.c"), .flags = &.{"-std=c11"} });
        local_tests.root_module.addCSourceFile(.{ .file = b.path("src/local/trusted_edit_native.c"), .flags = &.{"-std=c11"} });
        local_tests.root_module.addCSourceFile(.{ .file = b.path("src/local/secret_native.c"), .flags = &.{"-std=c11"} });
        local_tests.root_module.addSystemIncludePath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include" });
        local_tests.root_module.addLibraryPath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/lib" });
        local_tests.root_module.link_libc = true;
        if (std.mem.eql(u8, suite, "terminal-controller-tests") or std.mem.eql(u8, suite, "local-adapter-tests") or std.mem.eql(u8, suite, "trusted-edit-tests") or std.mem.eql(u8, suite, "terminal-execution-tests")) {
            // SessionHost's registry now contains public UI/service contracts.
            // These runners need the same linked ABI while remaining headless.
            local_tests.root_module.addImport("ui", zenit_dep.module("ui"));
            local_tests.root_module.addImport("zenit_app", zenit_dep.module("zenit_app"));
            local_tests.root_module.addImport("icon_ir", zenit_dep.module("icon_ir"));
            local_tests.root_module.addImport("generated_ssh_session", ssh_session_translate.createModule());
            local_tests.root_module.addImport("generated_ssh_channel", ssh_channel_translate.createModule());
            local_tests.root_module.addIncludePath(b.path("vendor/libssh2/include"));
            local_tests.root_module.addIncludePath(b.path("vendor/mbedtls/include"));
            local_tests.root_module.addIncludePath(b.path("src/proto/ssh"));
            local_tests.root_module.addCSourceFiles(.{ .files = &.{ "src/proto/ssh/libssh2_channel_shim.c", "src/proto/ssh/libssh2_session_shim.c" }, .flags = &.{"-std=c11"} });
            local_tests.root_module.addLibraryPath(b.path("vendor/libssh2/src/.libs"));
            local_tests.root_module.addLibraryPath(b.path("vendor/mbedtls/library"));
            linkVendorSsh(b, local_tests.root_module);
            local_tests.step.dependOn(&verify_ssh.step);
            local_tests.step.dependOn(&check_yix.step);
            local_tests.step.dependOn(&check_arch_gate.step);
            local_tests.root_module.linkSystemLibrary("z", .{});
            addCoreTextBridgeForTest(zenit_dep, local_tests);
            addBmcNative(b, local_tests.root_module);
            local_tests.root_module.addCSourceFile(.{ .file = zenit_dep.path("native/macos/metal_bridge.m"), .flags = &.{"-fobjc-arc"} });
            local_tests.root_module.linkFramework("Metal", .{});
            local_tests.root_module.linkFramework("QuartzCore", .{});
        }
        if (!std.mem.eql(u8, suite, "local-process-tests")) {
            // ZSH resolves its private module beside this isolated test binary,
            // exactly as the installed application does.
            const files = b.addWriteFiles();
            const runner_name = suite;
            const runner = files.addCopyFile(local_tests.getEmittedBin(), runner_name);
            _ = files.addCopyFile(zsh_bridge_file, "zw_ipc.so");
            _ = files.addCopyFile(execution_bridge_file, "zw_execution.so");
            _ = files.addCopyFile(secret_consumer_file, "zw_secret_consume.so");
            _ = files.addCopyFile(execution_guard_file, "zw_execution_guard");
            const trusted_run = std.Build.Step.Run.create(b, "run local integration tests");
            trusted_run.addFileArg(runner);
            local_tests_step.dependOn(&trusted_run.step);
            if (std.mem.eql(u8, suite, "trusted-edit-tests") or std.mem.eql(u8, suite, "terminal-execution-tests")) {
                b.step(if (std.mem.eql(u8, suite, "terminal-execution-tests")) "test-terminal-execution" else "test-trusted-edit", "Run isolated real ZSH integration tests").dependOn(&trusted_run.step);
            }
            if (std.mem.eql(u8, suite, "local-adapter-tests")) b.step("test-local-adapter", "Run local PTY adapter regressions").dependOn(&trusted_run.step);
        } else {
            const local_run = b.addRunArtifact(local_tests);
            local_tests_step.dependOn(&local_run.step);
        }
    }

    const notification_preview = b.addExecutable(.{ .name = "notification-preview", .root_module = b.createModule(.{
        .root_source_file = b.path("src/preview.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    selectRoot(b, notification_preview.root_module, "notification-preview");
    zenit.attach(zenit_dep, notification_preview);
    notification_preview.root_module.addSystemFrameworkPath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks" });
    notification_preview.root_module.addSystemIncludePath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include" });
    notification_preview.root_module.addLibraryPath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/lib" });
    b.step("test-notification-preview", "Build isolated native notification acceptance fixture").dependOn(&b.addInstallArtifact(notification_preview, .{}).step);
    const bmc_preview = b.addExecutable(.{ .name = "bmc-kvm-preview", .root_module = b.createModule(.{ .root_source_file = b.path("src/preview.zig"), .target = target, .optimize = optimize }) });
    selectRoot(b, bmc_preview.root_module, "bmc-kvm-preview");
    zenit.attach(zenit_dep, bmc_preview);
    bmc_preview.root_module.addImport("icon_ir", zenit_dep.module("icon_ir"));
    bmc_preview.root_module.addAnonymousImport("ui_font_assets", .{ .root_source_file = b.path("assets/fonts/native.zig") });
    bmc_preview.root_module.addCSourceFile(.{ .file = b.path("src/platform/ui_fonts.m"), .flags = &.{} });
    bmc_preview.root_module.addImport("generated_ssh_session", ssh_session_translate.createModule());
    bmc_preview.root_module.addImport("generated_ssh_channel", ssh_channel_translate.createModule());
    bmc_preview.root_module.addImport("generated_ghostty_vt", ghostty_translate.createModule());
    addBmcNative(b, bmc_preview.root_module);
    bmc_preview.root_module.addSystemFrameworkPath(.{ .cwd_relative = "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks" });
    bmc_preview.root_module.addSystemIncludePath(.{ .cwd_relative = "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include" });
    bmc_preview.root_module.addLibraryPath(.{ .cwd_relative = "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/lib" });
    b.step("bmc-kvm-preview", "Build the native KVM renderer acceptance fixture").dependOn(&b.addInstallArtifact(bmc_preview, .{}).step);
    const bmc_live = b.addExecutable(.{ .name = "bmc-live-readonly", .root_module = b.createModule(.{ .root_source_file = b.path("src/acceptance.zig"), .target = target, .optimize = optimize }) });
    selectRoot(b, bmc_live.root_module, "bmc-live-readonly");
    zenit.attach(zenit_dep, bmc_live);
    bmc_live.root_module.addImport("icon_ir", zenit_dep.module("icon_ir"));
    bmc_live.root_module.addAnonymousImport("ui_font_assets", .{ .root_source_file = b.path("assets/fonts/native.zig") });
    bmc_live.root_module.addImport("generated_ssh_session", ssh_session_translate.createModule());
    bmc_live.root_module.addImport("generated_ssh_channel", ssh_channel_translate.createModule());
    bmc_live.root_module.addImport("generated_ghostty_vt", ghostty_translate.createModule());
    bmc_live.root_module.addIncludePath(b.path("vendor/libssh2/include"));
    bmc_live.root_module.addIncludePath(b.path("src/proto/ssh"));
    bmc_live.root_module.addCSourceFiles(.{ .files = &.{ "src/proto/ssh/libssh2_channel_shim.c", "src/proto/ssh/libssh2_session_shim.c", "src/platform/macos_credentials.m", "src/platform/data_scope_lock.c", "src/platform/ui_fonts.m" }, .flags = &.{} });
    bmc_live.root_module.addLibraryPath(b.path("vendor/libssh2/src/.libs"));
    bmc_live.root_module.addLibraryPath(b.path("vendor/libghostty-vt"));
    linkVendorSsh(b, bmc_live.root_module);
    bmc_live.root_module.linkSystemLibrary("ghostty-vt", .{});
    addBmcNative(b, bmc_live.root_module);
    bmc_live.root_module.addSystemFrameworkPath(.{ .cwd_relative = "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks" });
    bmc_live.root_module.addSystemIncludePath(.{ .cwd_relative = "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include" });
    bmc_live.root_module.addLibraryPath(.{ .cwd_relative = "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/lib" });
    b.step("bmc-live-readonly", "Build the stdin-only read-only native BMC acceptance runner").dependOn(&b.addInstallArtifact(bmc_live, .{}).step);
    for ([_][]const u8{ "task-finish", "execution-result", "inventory-grant", "close-confirmation", "ai-empty-recent", "ai-recovery", "composer-interaction", "button-policy", "ai-launcher" }) |name| {
        const preview = b.addExecutable(.{ .name = b.fmt("{s}-preview", .{name}), .root_module = b.createModule(.{ .root_source_file = b.path("src/preview.zig"), .target = target, .optimize = optimize }) });
        selectRoot(b, preview.root_module, preview.name);
        zenit.attach(zenit_dep, preview);
        preview.root_module.addImport("icon_ir", zenit_dep.module("icon_ir"));
        if (std.mem.eql(u8, name, "close-confirmation") or std.mem.eql(u8, name, "ai-empty-recent") or std.mem.eql(u8, name, "ai-recovery") or std.mem.eql(u8, name, "composer-interaction") or std.mem.eql(u8, name, "ai-launcher")) {
            // Match the production UI font chain in the native preview.
            preview.root_module.addAnonymousImport("ui_font_assets", .{ .root_source_file = b.path("assets/fonts/native.zig") });
            preview.root_module.addCSourceFile(.{ .file = b.path("src/platform/ui_fonts.m"), .flags = &.{} });
        }
        if (std.mem.eql(u8, name, "ai-empty-recent")) preview.root_module.addAnonymousImport("app_icon_assets", .{ .root_source_file = b.path("assets/macos/icons.zig") });
        preview.root_module.addSystemFrameworkPath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks" });
        preview.root_module.addSystemIncludePath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include" });
        preview.root_module.addLibraryPath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/lib" });
        b.step(b.fmt("{s}-preview", .{name}), b.fmt("Build isolated production {s} UI acceptance window", .{name})).dependOn(&b.addInstallArtifact(preview, .{}).step);
    }

    const font_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/tests_font.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    font_tests.root_module.addImport("zenit_app", zenit_dep.module("zenit_app"));
    addCoreTextBridgeForTest(zenit_dep, font_tests);
    font_tests.root_module.addAnonymousImport("ui_font_assets", .{ .root_source_file = b.path("assets/fonts/native.zig") });
    font_tests.root_module.addCSourceFile(.{ .file = b.path("src/platform/ui_fonts.m"), .flags = &.{} });
    b.step("test-font", "Resolve appearance fonts and verify actual native metrics without windows").dependOn(&b.addRunArtifact(font_tests).step);

    const appearance_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/tests_appearance.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    appearance_tests.root_module.addImport("ui", zenit_dep.module("ui"));
    appearance_tests.root_module.addImport("zenit_app", zenit_dep.module("zenit_app"));
    appearance_tests.root_module.addImport("icon_ir", zenit_dep.module("icon_ir"));
    // Production terminal event tests instantiate the real input path without
    // opening an SSH connection. Supply the same native ABI as the app.
    appearance_tests.root_module.addImport("generated_ghostty_vt", ghostty_translate.createModule());
    appearance_tests.root_module.addImport("generated_ssh_session", ssh_session_translate.createModule());
    appearance_tests.root_module.addImport("generated_ssh_channel", ssh_channel_translate.createModule());
    appearance_tests.root_module.addLibraryPath(b.path("vendor/libghostty-vt"));
    appearance_tests.root_module.linkSystemLibrary("ghostty-vt", .{});
    appearance_tests.root_module.linkSystemLibrary("curl", .{});
    appearance_tests.root_module.addIncludePath(b.path("vendor/libssh2/include"));
    appearance_tests.root_module.addIncludePath(b.path("vendor/mbedtls/include"));
    appearance_tests.root_module.addIncludePath(b.path("src/proto/ssh"));
    appearance_tests.root_module.addCSourceFiles(.{ .files = &.{ "src/proto/ssh/libssh2_channel_shim.c", "src/proto/ssh/libssh2_session_shim.c", "src/local/darwin_process.c", "src/ai/mcp_native.c", "src/local/trusted_edit_native.c", "src/local/secret_native.c" }, .flags = &.{"-std=c11"} });
    appearance_tests.root_module.addLibraryPath(b.path("vendor/libssh2/src/.libs"));
    appearance_tests.root_module.addLibraryPath(b.path("vendor/mbedtls/library"));
    linkVendorSsh(b, appearance_tests.root_module);
    appearance_tests.step.dependOn(&verify_ssh.step);
    appearance_tests.step.dependOn(&check_yix.step);
    appearance_tests.step.dependOn(&check_arch_gate.step);
    appearance_tests.root_module.linkSystemLibrary("z", .{});

    addCoreTextBridgeForTest(zenit_dep, appearance_tests);
    addBmcNative(b, appearance_tests.root_module);
    appearance_tests.root_module.addCSourceFile(.{ .file = zenit_dep.path("native/macos/metal_bridge.m"), .flags = &.{"-fobjc-arc"} });
    appearance_tests.root_module.linkFramework("Metal", .{});
    appearance_tests.root_module.linkFramework("QuartzCore", .{});
    appearance_tests.root_module.link_libc = true;
    for ([_][]const u8{ "CoreFoundation", "ImageIO", "CoreGraphics" }) |framework| {
        appearance_tests.root_module.linkFramework(framework, .{});
    }
    appearance_tests.root_module.addSystemFrameworkPath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks" });
    appearance_tests.root_module.addSystemIncludePath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include" });
    appearance_tests.root_module.addLibraryPath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/lib" });
    // Appearance imports collect headless terminal integration tests too. Keep
    // their private shell modules beside the runner, as for root/UI tests.
    const appearance_test_files = b.addWriteFiles();
    const appearance_test_binary = appearance_test_files.addCopyFile(appearance_tests.getEmittedBin(), "appearance-tests");
    _ = appearance_test_files.addCopyFile(zsh_bridge_file, "zw_ipc.so");
    _ = appearance_test_files.addCopyFile(execution_bridge_file, "zw_execution.so");
    _ = appearance_test_files.addCopyFile(secret_consumer_file, "zw_secret_consume.so");
    _ = appearance_test_files.addCopyFile(execution_guard_file, "zw_execution_guard");
    const run_appearance_tests = std.Build.Step.Run.create(b, "run appearance tests");
    run_appearance_tests.addFileArg(appearance_test_binary);
    b.step("test-appearance", "Run headless appearance asset, theme and configuration tests").dependOn(&run_appearance_tests.step);

    // transfer_panel 的整面板装配测试要跑 zenit 布局 → 独立测试模块（zenit
    // 注释警告：C 源挂在被 exe 依赖的模块上会传播，core 挂了会让 exe 里
    // zenit .m 桥出现两份 → duplicate symbol。独立模块只在此路径挂 .m）。
    const ui_test_filter = b.option([]const u8, "ui-test-filter", "Run only matching UI tests");
    const ui_tests = b.addTest(.{ .filters = if (ui_test_filter) |filter| &.{filter} else &.{}, .root_module = b.createModule(.{
        .root_source_file = b.path("src/tests_ui.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    ui_tests.root_module.addImport("ui", zenit_dep.module("ui"));
    ui_tests.root_module.addImport("zenit_app", zenit_dep.module("zenit_app"));
    ui_tests.root_module.addImport("icon_ir", zenit_dep.module("icon_ir"));
    // Production terminal event tests instantiate the real input path without
    // opening an SSH connection. Supply the same native ABI as the app.
    ui_tests.root_module.addImport("generated_ghostty_vt", ghostty_translate.createModule());
    ui_tests.root_module.addImport("generated_ssh_session", ssh_session_translate.createModule());
    ui_tests.root_module.addImport("generated_ssh_channel", ssh_channel_translate.createModule());
    ui_tests.root_module.addLibraryPath(b.path("vendor/libghostty-vt"));
    ui_tests.root_module.linkSystemLibrary("ghostty-vt", .{});
    ui_tests.root_module.linkSystemLibrary("curl", .{});
    ui_tests.root_module.addIncludePath(b.path("vendor/libssh2/include"));
    ui_tests.root_module.addIncludePath(b.path("vendor/mbedtls/include"));
    ui_tests.root_module.addIncludePath(b.path("src/proto/ssh"));
    ui_tests.root_module.addCSourceFiles(.{ .files = &.{ "src/proto/ssh/libssh2_channel_shim.c", "src/proto/ssh/libssh2_session_shim.c", "src/local/darwin_process.c", "src/ai/mcp_native.c", "src/local/trusted_edit_native.c", "src/local/secret_native.c" }, .flags = &.{"-std=c11"} });
    ui_tests.root_module.addLibraryPath(b.path("vendor/libssh2/src/.libs"));
    ui_tests.root_module.addLibraryPath(b.path("vendor/mbedtls/library"));
    linkVendorSsh(b, ui_tests.root_module);
    ui_tests.step.dependOn(&verify_ssh.step);
    ui_tests.step.dependOn(&check_yix.step);
    ui_tests.step.dependOn(&check_arch_gate.step);
    ui_tests.root_module.linkSystemLibrary("z", .{});

    addCoreTextBridgeForTest(zenit_dep, ui_tests);
    addBmcNative(b, ui_tests.root_module);
    ui_tests.root_module.addCSourceFile(.{ .file = zenit_dep.path("native/macos/metal_bridge.m"), .flags = &.{"-fobjc-arc"} });
    ui_tests.root_module.linkFramework("Metal", .{});
    ui_tests.root_module.linkFramework("QuartzCore", .{});
    ui_tests.root_module.linkFramework("JavaScriptCore", .{});
    const ui_test_files = b.addWriteFiles();
    const ui_test_binary = ui_test_files.addCopyFile(ui_tests.getEmittedBin(), "ui-tests");
    _ = ui_test_files.addCopyFile(zsh_bridge_file, "zw_ipc.so");
    _ = ui_test_files.addCopyFile(execution_bridge_file, "zw_execution.so");
    _ = ui_test_files.addCopyFile(secret_consumer_file, "zw_secret_consume.so");
    _ = ui_test_files.addCopyFile(execution_guard_file, "zw_execution_guard");
    const run_ui_tests = std.Build.Step.Run.create(b, "run transfer-panel and layout tests");
    run_ui_tests.addFileArg(ui_test_binary);
    b.step("test-ui", "Run transfer-panel/zenit-layout tests").dependOn(&run_ui_tests.step);
    // Compile every test body of the two aggregate roots and of the standalone roots
    // without running them. A filter (`-Dtest-filter` / `-Dui-test-filter`, or the fixed
    // `.filters` of test-update / test-bmc / test-plugin-fixture / test-builtin-records /
    // test-compaction-e2e / test-ai-gateway) skips semantic analysis of non-matching
    // tests, so a filtered run cannot serve as a compile check. The standalone roots get
    // an extra unfiltered compile from the same addStandaloneTest() configuration as their
    // run binary; this step refuses filters.
    const compile_tests_step = b.step("compile-tests", "Compile all unit, UI and standalone-root tests (no filter) without running them");
    if (root_test_filter != null or ui_test_filter != null) {
        compile_tests_step.dependOn(&b.addFail("compile-tests must not be combined with -Dtest-filter / -Dui-test-filter").step);
    } else {
        compile_tests_step.dependOn(&tests.step);
        compile_tests_step.dependOn(&ui_tests.step);
        for (std.enums.values(StandaloneTestRoot)) |root| {
            const unfiltered = addStandaloneTest(standalone, root, .{ .name = b.fmt("{s}-tests-unfiltered", .{@tagName(root)}), .unfiltered_closure = true });
            compile_tests_step.dependOn(&unfiltered.step);
        }
    }
    b.step("ssh-shell-product-acceptance", "Export product lifecycle tests for controlled SSH loopback; select with -Dtest-filter").dependOn(&b.addInstallFile(root_test_binary, "bin/ssh-shell-product-tests").step);

    // API-v2 acceptance runs separately so the non-terminal fixture is never
    // registered or linked by the production executable.
    const plugin_tests = addStandaloneTest(standalone, .plugin_fixture, .{ .filters = &.{"fixture "} });
    b.step("test-plugin-fixture", "Run the non-terminal plugin acceptance contract").dependOn(&b.addRunArtifact(plugin_tests).step);

    const transport_runner = b.addExecutable(.{ .name = "connection-transport-runner", .root_module = b.createModule(.{
        .root_source_file = b.path("src/acceptance.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    selectRoot(b, transport_runner.root_module, "connection-transport-runner");
    transport_runner.root_module.addImport("generated_ssh_session", ssh_session_translate.createModule());
    transport_runner.root_module.addImport("generated_ssh_channel", ssh_channel_translate.createModule());
    transport_runner.root_module.addIncludePath(b.path("vendor/libssh2/include"));
    transport_runner.root_module.addIncludePath(b.path("vendor/mbedtls/include"));
    transport_runner.root_module.addIncludePath(b.path("src/proto/ssh"));
    transport_runner.root_module.addCSourceFiles(.{ .files = &.{ "src/proto/ssh/libssh2_channel_shim.c", "src/proto/ssh/libssh2_session_shim.c" }, .flags = &.{"-std=c11"} });
    transport_runner.root_module.addLibraryPath(b.path("vendor/libssh2/src/.libs"));
    transport_runner.root_module.addLibraryPath(b.path("vendor/mbedtls/library"));
    transport_runner.root_module.addSystemIncludePath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include" });
    transport_runner.root_module.addLibraryPath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/lib" });
    linkVendorSsh(b, transport_runner.root_module);
    transport_runner.step.dependOn(&verify_ssh.step);
    transport_runner.root_module.linkSystemLibrary("z", .{});
    b.step("transport-acceptance", "Build the opt-in real SSH independent transport runner").dependOn(&b.addInstallArtifact(transport_runner, .{}).step);

    const hardening = b.step("ssh-hardening-acceptance", "Build owned SSH timeout and liveness acceptance runners");
    for ([_]struct { name: []const u8 }{
        .{ .name = "ssh-connection-wait-runner" },
        .{ .name = "ssh-hardening-runner" },
        .{ .name = "ssh-auth-loopback-runner" },
        .{ .name = "ssh-exec-service-runner" },
    }) |spec| {
        const runner = b.addExecutable(.{ .name = spec.name, .root_module = b.createModule(.{
            .root_source_file = b.path("src/acceptance.zig"),
            .target = target,
            .optimize = optimize,
        }) });
        selectRoot(b, runner.root_module, spec.name);
        runner.step.dependOn(&verify_ssh.step);
        runner.root_module.addImport("generated_ssh_session", ssh_session_translate.createModule());
        runner.root_module.addImport("generated_ssh_channel", ssh_channel_translate.createModule());
        runner.root_module.addIncludePath(b.path("vendor/libssh2/include"));
        runner.root_module.addIncludePath(b.path("vendor/mbedtls/include"));
        runner.root_module.addIncludePath(b.path("src/proto/ssh"));
        runner.root_module.addCSourceFiles(.{ .files = &.{ "src/proto/ssh/libssh2_channel_shim.c", "src/proto/ssh/libssh2_session_shim.c" }, .flags = &.{"-std=c11"} });
        runner.root_module.addLibraryPath(b.path("vendor/libssh2/src/.libs"));
        runner.root_module.addLibraryPath(b.path("vendor/mbedtls/library"));
        linkVendorSsh(b, runner.root_module);
        runner.root_module.linkSystemLibrary("z", .{});
        runner.root_module.addSystemIncludePath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include" });
        runner.root_module.addLibraryPath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/lib" });
        runner.root_module.link_libc = true;
        hardening.dependOn(&b.addInstallArtifact(runner, .{}).step);
        if (std.mem.eql(u8, spec.name, "ssh-exec-service-runner")) b.step("ssh-exec-acceptance", "Build isolated SSH exec stdin and lifecycle acceptance runner").dependOn(&b.addInstallArtifact(runner, .{}).step);
    }

    const disconnect_acceptance = b.step("ssh-disconnect-acceptance", "Build headless explicit SSH disconnect lifecycle acceptance runner");
    const bootstrap_acceptance = b.step("ssh-bootstrap-acceptance", "Build headless production BootstrapV1 loopback acceptance runner");
    const shell_execution_acceptance = b.step("ssh-shell-execution-acceptance", "Build same-shell SSH execution loopback acceptance runner");
    const forward_acceptance = b.step("forward-acceptance", "Build real forwarding and production Worker/Relay lifecycle acceptance runners");
    const shared_acceptance = b.step("shared-connection-acceptance", "Build independent SSH channel and reconnect acceptance runner");
    const reconnect_acceptance = b.step("reconnect-acceptance", "Build original-terminal reconnect acceptance runner");
    for ([_]struct { name: []const u8 }{
        .{ .name = "ssh-disconnect-runner" },
        .{ .name = "ssh-bootstrap-runner" },
        .{ .name = "ssh-shell-execution-runner" },
        .{ .name = "fixed-forward-runner" },
        .{ .name = "socks-worker-host-runner" },
        .{ .name = "forward-load-runner" },
        .{ .name = "ssh-connection-details-runner" },
        .{ .name = "ssh-reconnect-loopback-runner" },
        .{ .name = "ssh-shared-connection-runner" },
    }) |runner| {
        const fixed_forward_runner = b.addExecutable(.{ .name = runner.name, .root_module = b.createModule(.{
            .root_source_file = b.path("src/acceptance.zig"),
            .target = target,
            .optimize = optimize,
        }) });
        selectRoot(b, fixed_forward_runner.root_module, runner.name);
        fixed_forward_runner.root_module.addImport("ui", zenit_dep.module("ui"));
        fixed_forward_runner.root_module.addImport("icon_ir", zenit_dep.module("icon_ir"));
        fixed_forward_runner.root_module.addImport("generated_ssh_session", ssh_session_translate.createModule());
        fixed_forward_runner.root_module.addImport("generated_ssh_channel", ssh_channel_translate.createModule());
        fixed_forward_runner.root_module.addImport("generated_ghostty_vt", ghostty_translate.createModule());
        fixed_forward_runner.root_module.addLibraryPath(b.path("vendor/libghostty-vt"));
        fixed_forward_runner.root_module.linkSystemLibrary("ghostty-vt", .{});
        fixed_forward_runner.root_module.addIncludePath(b.path("vendor/libssh2/include"));
        fixed_forward_runner.root_module.addIncludePath(b.path("vendor/mbedtls/include"));
        fixed_forward_runner.root_module.addIncludePath(b.path("src/proto/ssh"));
        fixed_forward_runner.root_module.addCSourceFiles(.{ .files = &.{ "src/proto/ssh/libssh2_channel_shim.c", "src/proto/ssh/libssh2_session_shim.c" }, .flags = &.{"-std=c11"} });
        fixed_forward_runner.root_module.addLibraryPath(b.path("vendor/libssh2/src/.libs"));
        fixed_forward_runner.root_module.addLibraryPath(b.path("vendor/mbedtls/library"));
        fixed_forward_runner.root_module.addSystemIncludePath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include" });
        fixed_forward_runner.root_module.addLibraryPath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/lib" });
        linkVendorSsh(b, fixed_forward_runner.root_module);
        fixed_forward_runner.step.dependOn(&verify_ssh.step);
        fixed_forward_runner.root_module.linkSystemLibrary("z", .{});
        addCoreTextBridgeForTest(zenit_dep, fixed_forward_runner);
        addBmcNative(b, fixed_forward_runner.root_module);
        if (std.mem.eql(u8, runner.name, "ssh-disconnect-runner") or std.mem.eql(u8, runner.name, "ssh-bootstrap-runner") or std.mem.eql(u8, runner.name, "ssh-shell-execution-runner") or std.mem.eql(u8, runner.name, "ssh-reconnect-loopback-runner") or std.mem.eql(u8, runner.name, "ssh-shared-connection-runner") or std.mem.eql(u8, runner.name, "socks-worker-host-runner") or std.mem.eql(u8, runner.name, "forward-load-runner")) {
            fixed_forward_runner.root_module.linkSystemLibrary("curl", .{});
            fixed_forward_runner.root_module.addCSourceFiles(.{ .files = &.{ "src/local/darwin_process.c", "src/ai/mcp_native.c", "src/local/trusted_edit_native.c", "src/local/secret_native.c" }, .flags = &.{"-std=c11"} });
            fixed_forward_runner.root_module.addCSourceFile(.{ .file = b.path("src/platform/macos_credentials.m"), .flags = &.{} });
            fixed_forward_runner.root_module.linkFramework("Security", .{});
        }
        const runner_install = b.addInstallArtifact(fixed_forward_runner, .{});
        forward_acceptance.dependOn(&runner_install.step);
        if (std.mem.eql(u8, runner.name, "ssh-disconnect-runner")) disconnect_acceptance.dependOn(&runner_install.step);
        if (std.mem.eql(u8, runner.name, "ssh-bootstrap-runner")) bootstrap_acceptance.dependOn(&runner_install.step);
        if (std.mem.eql(u8, runner.name, "ssh-shell-execution-runner")) shell_execution_acceptance.dependOn(&runner_install.step);
        if (std.mem.eql(u8, runner.name, "ssh-shared-connection-runner")) shared_acceptance.dependOn(&runner_install.step);
        if (std.mem.eql(u8, runner.name, "ssh-reconnect-loopback-runner")) reconnect_acceptance.dependOn(&runner_install.step);
    }

    const forward_preview = b.addExecutable(.{ .name = "forward-config-preview", .root_module = b.createModule(.{
        .root_source_file = b.path("src/preview.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    selectRoot(b, forward_preview.root_module, "forward-config-preview");
    zenit.attach(zenit_dep, forward_preview);
    forward_preview.root_module.addImport("generated_ssh_session", ssh_session_translate.createModule());
    forward_preview.root_module.addImport("generated_ssh_channel", ssh_channel_translate.createModule());
    forward_preview.root_module.addIncludePath(b.path("vendor/libssh2/include"));
    forward_preview.root_module.addIncludePath(b.path("vendor/mbedtls/include"));
    forward_preview.root_module.addIncludePath(b.path("src/proto/ssh"));
    forward_preview.root_module.addCSourceFiles(.{ .files = &.{ "src/proto/ssh/libssh2_channel_shim.c", "src/proto/ssh/libssh2_session_shim.c" }, .flags = &.{"-std=c11"} });
    forward_preview.root_module.addLibraryPath(b.path("vendor/libssh2/src/.libs"));
    forward_preview.root_module.addLibraryPath(b.path("vendor/mbedtls/library"));
    linkVendorSsh(b, forward_preview.root_module);
    forward_preview.step.dependOn(&verify_ssh.step);
    forward_preview.root_module.linkSystemLibrary("z", .{});
    forward_preview.root_module.addSystemFrameworkPath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks" });
    forward_preview.root_module.addSystemIncludePath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include" });
    forward_preview.root_module.addLibraryPath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/lib" });
    b.step("forward-config-preview", "Build isolated actual native forwarding config for click acceptance").dependOn(&b.addInstallArtifact(forward_preview, .{}).step);

    const gateway_tests = addStandaloneTest(standalone, .ai_gateway, .{ .filters = &.{"API2 LIVE"} });
    const run_gateway_tests = b.addRunArtifact(gateway_tests);
    // Endpoint/model/opt-in are supplied at execution time; a cached success
    // from another environment is never evidence of a live gateway run.
    run_gateway_tests.has_side_effects = true;
    b.step("test-ai-gateway", "Run opt-in production gateway tool/image acceptance").dependOn(&run_gateway_tests.step);

    const environment_probe = b.addExecutable(.{ .name = "application-environment-contract", .root_module = b.createModule(.{
        .root_source_file = b.path("src/acceptance.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    }) });
    selectRoot(b, environment_probe.root_module, "application-environment-contract");
    const formal_environment = b.createModule(.{ .root_source_file = zenit_dep.path("src/environment.zig"), .target = target, .optimize = optimize, .link_libc = true });
    const formal_environment_options = b.addOptions();
    formal_environment_options.addOption(bool, "enabled", false);
    formal_environment_options.addOption(bool, "formal_probe", true);
    formal_environment.addOptions("automation_options", formal_environment_options);
    environment_probe.root_module.addImport("formal_environment", formal_environment);
    const run_environment_probe = b.addRunArtifact(environment_probe);
    // A formal build has no home override: these must not move any path.
    for ([_][2][]const u8{ .{ "HOME", "/private/tmp/zw-formal-probe-home" }, .{ "CFFIXED_USER_HOME", "/private/tmp/zw-formal-probe-fixed" }, .{ "ZEROWORK_DATA_DIR", "/private/tmp/zw-formal-probe-data" }, .{ "ZEROWORK_TEST_HOME", "/private/tmp/zw-formal-probe-test" } }) |entry| run_environment_probe.setEnvironmentVariable(entry[0], entry[1]);
    run_environment_probe.has_side_effects = true;
    b.step("test-app-environment", "Verify formal defaults ignore process environment overrides").dependOn(&run_environment_probe.step);

    // Standalone entries that used to be run with `zig test <file>` from the src/ root.
    // After P1 their files live in subdirectories, which cannot be module roots (YIX_SPIKE V-1),
    // so they are selected through src/acceptance.zig like the other acceptance runners.
    const builtin_records_tests = addStandaloneTest(standalone, .builtin_records, .{ .filters = &.{"builtin_records"} });
    b.step("test-builtin-records", "Run the standalone builtin records composite-document suite (e2e/builtin_records_test.sh)").dependOn(&b.addRunArtifact(builtin_records_tests).step);

    const compaction_tests = addStandaloneTest(standalone, .compaction_e2e, .{ .filters = &.{"compaction real"} });
    const run_compaction_tests = b.addRunArtifact(compaction_tests);
    // Talks to the loopback model server started by e2e/ai_context_compaction.py; never cache.
    run_compaction_tests.has_side_effects = true;
    b.step("test-compaction-e2e", "Run real-HTTP context compaction tests against the e2e/ai_context_compaction.py loopback server").dependOn(&run_compaction_tests.step);

    const applog_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/acceptance.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    }) });
    selectRoot(b, applog_tests.root_module, "applog-tests");
    b.step("test-applog", "Run focused applog writer/flush/shutdown regressions").dependOn(&b.addRunArtifact(applog_tests).step);
}

/// libssh2 is compiled against the pinned vendor Mbed TLS (vendor/.ssh-build-receipt.json).
/// Link both static archives by path. `linkSystemLibrary("mbedcrypto")` consults pkg-config
/// first and picked up a host Mbed TLS (Homebrew 3.6.3 dylibs) whose ABI differs from the
/// 3.6.7 headers libssh2 was built with, which broke SSH key exchange (REQUESTS #54).
/// check-ssh-link rejects any linked binary that still loads an Mbed TLS / libssh2 dylib.
fn linkVendorSsh(b: *std.Build, module: *std.Build.Module) void {
    module.addObjectFile(b.path("vendor/libssh2/src/.libs/libssh2.a"));
    module.addObjectFile(b.path("vendor/mbedtls/library/libmbedcrypto.a"));
}

fn addCoreTextBridgeForTest(zenit_dep: *std.Build.Dependency, exe: *std.Build.Step.Compile) void {
    exe.root_module.addCSourceFile(.{
        .file = zenit_dep.path("native/macos/coretext_bridge.m"),
        .flags = &.{"-fobjc-arc"},
    });
    // IOSurface: zenit image/texture paths; JavaScriptCore: MCP schema bridge reached by host modules.
    for ([_][]const u8{ "CoreText", "CoreGraphics", "CoreFoundation", "CFNetwork", "Foundation", "ImageIO", "IOSurface", "JavaScriptCore" }) |fw| {
        exe.root_module.linkFramework(fw, .{});
    }
    const sdk = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";
    exe.root_module.addSystemFrameworkPath(.{ .cwd_relative = sdk ++ "/System/Library/Frameworks" });
    exe.root_module.addSystemIncludePath(.{ .cwd_relative = sdk ++ "/usr/include" });
    // libobjc.A.tbd 的解析需要 SDK 的 usr/lib 在搜索路径（与 exe/mockup 同款）。
    exe.root_module.addLibraryPath(.{ .cwd_relative = sdk ++ "/usr/lib" });
    exe.root_module.link_libc = true;
}

// Capture metadata on each build invocation so packaged binaries retain their
// source identity and timestamp even when launched outside the checkout.
fn buildCommand(b: *std.Build, argv: []const []const u8) ?[]const u8 {
    // Git state and wall time are not tracked configure inputs. Zig 0.17 can
    // otherwise reuse the entire graph, including stale generated options.
    b.graph.poisonCache();
    return switch (b.runFallible(argv, .{ .cwd = .{ .path = b.root.joinString(b.allocator, "") catch @panic("OOM") }, .stderr_behavior = .ignore })) {
        .success => |stdout| std.mem.trim(u8, stdout, " \t\r\n"),
        else => null,
    };
}

fn addUrlFetchFrameworks(module: *std.Build.Module) void {
    module.linkFramework("CoreFoundation", .{});
    module.linkFramework("CFNetwork", .{});
    module.linkFramework("JavaScriptCore", .{});
}

/// The BMC library and every test consumer use the same pinned crypto/codec ABI.
fn addBmcNative(b: *std.Build, module: *std.Build.Module) void {
    module.addIncludePath(b.path("vendor/mbedtls/include"));
    module.addIncludePath(b.path("src/plugins/bmc_ikvm/protocol"));
    module.addCSourceFiles(.{ .files = &.{
        "src/platform/bmc_tls_trust.c",
        "src/plugins/bmc_ikvm/protocol/tls_shim.c",
        "src/plugins/bmc_ikvm/protocol/zlib_shim.c",
        "src/plugins/bmc_ikvm/platform/jpeg.c",
    }, .flags = &.{"-std=c11"} });
    // Static vendor archives by path, never pkg-config (see linkVendorSsh, REQUESTS #54).
    for ([_][]const u8{ "libmbedtls.a", "libmbedx509.a", "libmbedcrypto.a" }) |archive| module.addObjectFile(b.path(b.fmt("vendor/mbedtls/library/{s}", .{archive})));
    module.linkSystemLibrary("z", .{});
    for ([_][]const u8{ "Security", "CoreFoundation", "CoreGraphics", "ImageIO", "LocalAuthentication", "Foundation" }) |framework| module.linkFramework(framework, .{});
    module.link_libc = true;
}

/// Module roots must stay in src/ (YIX_SPIKE.md V-1): preview runners, acceptance
/// runners and the test-local suites share the multiplexing roots src/preview.zig,
/// src/acceptance.zig and src/tests_local.zig, which pick the implementation file at
/// comptime from `root_select.name` (the artifact name). ARCHITECTURE_PLAN.md §5.4.
/// -Dtest-mode of this build, for the multiplexed roots (src/preview.zig,
/// src/acceptance.zig) that export the launch-guard marker in test builds.
var select_root_test_mode = false;

fn selectRoot(b: *std.Build, module: *std.Build.Module, name: []const u8) void {
    const options = b.addOptions();
    options.addOption([]const u8, "name", name);
    options.addOption(bool, "test_mode", select_root_test_mode);
    module.addOptions("root_select", options);
}

/// Standalone test roots outside the two aggregate roots (src/tests.zig, src/tests_ui.zig).
/// Each has a fixed-filter run step; addStandaloneTest() is the single source of their
/// module configuration so a filtered run binary and an unfiltered compile check agree.
const StandaloneTestRoot = enum { update, bmc, plugin_fixture, builtin_records, compaction_e2e, ai_gateway };

const StandaloneTestContext = struct {
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    zenit_dep: *std.Build.Dependency,
    ghostty_translate: *std.Build.Step.TranslateC,
    ssh_session_translate: *std.Build.Step.TranslateC,
    ssh_channel_translate: *std.Build.Step.TranslateC,
    verify_ssh: *std.Build.Step,
    check_yix: *std.Build.Step,
    check_arch_gate: *std.Build.Step,
};

const StandaloneTestOptions = struct {
    name: []const u8 = "test",
    filters: []const []const u8 = &.{},
    /// Set only for the unfiltered compile-tests variant. Without a filter, the
    /// src/acceptance.zig roots analyze every test of every file their implementation
    /// imports, and that closure reaches files importing `ui` / `zenit_app` / `icon_ir` /
    /// the ssh and ghostty translate-c modules, which the fixed filter never reaches.
    /// The run binaries keep their original configuration; this only adds those imports.
    unfiltered_closure: bool = false,
};

fn addStandaloneTest(ctx: StandaloneTestContext, root: StandaloneTestRoot, options: StandaloneTestOptions) *std.Build.Step.Compile {
    const b = ctx.b;
    const zenit_dep = ctx.zenit_dep;
    const sdk = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";
    const root_source: []const u8 = switch (root) {
        .update => "src/tests_update.zig",
        .bmc => "src/tests_bmc.zig",
        .plugin_fixture => "src/tests_plugin_fixture.zig",
        .builtin_records, .compaction_e2e, .ai_gateway => "src/acceptance.zig",
    };
    const tests = b.addTest(.{ .name = options.name, .filters = options.filters, .root_module = b.createModule(.{
        .root_source_file = b.path(root_source),
        .target = ctx.target,
        .optimize = ctx.optimize,
    }) });
    const module = tests.root_module;
    switch (root) {
        .update => {
            module.addImport("ui", zenit_dep.module("ui"));
            module.addImport("icon_ir", zenit_dep.module("icon_ir"));
            module.addImport("generated_ssh_channel", ctx.ssh_channel_translate.createModule());
            module.addImport("generated_ssh_session", ctx.ssh_session_translate.createModule());
            module.addImport("generated_ghostty_vt", ctx.ghostty_translate.createModule());
        },
        .bmc => {
            module.addImport("ui", zenit_dep.module("ui"));
            module.addImport("icon_ir", zenit_dep.module("icon_ir"));
            module.addImport("zenit_app", zenit_dep.module("zenit_app"));
            module.addImport("generated_ssh_session", ctx.ssh_session_translate.createModule());
            module.addImport("generated_ssh_channel", ctx.ssh_channel_translate.createModule());
            module.addImport("generated_ghostty_vt", ctx.ghostty_translate.createModule());
            module.addIncludePath(b.path("vendor/libssh2/include"));
            module.addIncludePath(b.path("src/proto/ssh"));
            module.addCSourceFiles(.{ .files = &.{
                "src/proto/ssh/libssh2_channel_shim.c", "src/proto/ssh/libssh2_session_shim.c",
                "src/platform/macos_credentials.m",     "src/platform/data_scope_lock.c",
                "src/local/darwin_process.c",           "src/ai/mcp_native.c",
                "src/local/trusted_edit_native.c",      "src/local/secret_native.c",
            }, .flags = &.{} });
            module.addLibraryPath(b.path("vendor/libssh2/src/.libs"));
            module.addLibraryPath(b.path("vendor/libghostty-vt"));
            linkVendorSsh(b, module);
            module.linkSystemLibrary("ghostty-vt", .{});
            module.linkSystemLibrary("curl", .{});
            addCoreTextBridgeForTest(zenit_dep, tests);
            addBmcNative(b, module);
            tests.step.dependOn(ctx.verify_ssh);
            tests.step.dependOn(ctx.check_yix);
            tests.step.dependOn(ctx.check_arch_gate);
        },
        .plugin_fixture => {
            module.addImport("ui", zenit_dep.module("ui"));
            module.addImport("zenit_app", zenit_dep.module("zenit_app"));
            module.addImport("icon_ir", zenit_dep.module("icon_ir"));
            module.addImport("generated_ghostty_vt", ctx.ghostty_translate.createModule());
            module.addImport("generated_ssh_session", ctx.ssh_session_translate.createModule());
            module.addImport("generated_ssh_channel", ctx.ssh_channel_translate.createModule());
            module.addLibraryPath(b.path("vendor/libghostty-vt"));
            module.linkSystemLibrary("ghostty-vt", .{});
            module.linkSystemLibrary("curl", .{});
            module.addIncludePath(b.path("vendor/libssh2/include"));
            module.addIncludePath(b.path("vendor/mbedtls/include"));
            module.addIncludePath(b.path("src/proto/ssh"));
            module.addCSourceFiles(.{ .files = &.{ "src/proto/ssh/libssh2_channel_shim.c", "src/proto/ssh/libssh2_session_shim.c", "src/local/darwin_process.c", "src/ai/mcp_native.c", "src/local/trusted_edit_native.c", "src/local/secret_native.c" }, .flags = &.{"-std=c11"} });
            module.addLibraryPath(b.path("vendor/libssh2/src/.libs"));
            module.addLibraryPath(b.path("vendor/mbedtls/library"));
            linkVendorSsh(b, module);
            tests.step.dependOn(ctx.verify_ssh);
            tests.step.dependOn(ctx.check_yix);
            tests.step.dependOn(ctx.check_arch_gate);
            module.linkSystemLibrary("z", .{});
            addCoreTextBridgeForTest(zenit_dep, tests);
            addBmcNative(b, module);
            module.addCSourceFile(.{ .file = zenit_dep.path("native/macos/metal_bridge.m"), .flags = &.{"-fobjc-arc"} });
            module.linkFramework("Metal", .{});
            module.linkFramework("QuartzCore", .{});
        },
        .builtin_records => {
            module.link_libc = true;
            selectRoot(b, module, "builtin-records-tests");
            module.addImport("generated_ghostty_vt", ctx.ghostty_translate.createModule());
            module.addLibraryPath(b.path("vendor/libghostty-vt"));
            module.linkSystemLibrary("ghostty-vt", .{});
        },
        .compaction_e2e => {
            module.link_libc = true;
            selectRoot(b, module, "compaction-e2e-tests");
            for ([_][]const u8{ "CoreFoundation", "CoreGraphics", "ImageIO" }) |framework| module.linkFramework(framework, .{});
            module.addSystemFrameworkPath(.{ .cwd_relative = sdk ++ "/System/Library/Frameworks" });
            module.addSystemIncludePath(.{ .cwd_relative = sdk ++ "/usr/include" });
            module.addLibraryPath(.{ .cwd_relative = sdk ++ "/usr/lib" });
        },
        .ai_gateway => {
            selectRoot(b, module, "ai-gateway");
            module.link_libc = true;
            for ([_][]const u8{ "CoreFoundation", "ImageIO", "CoreGraphics" }) |framework| module.linkFramework(framework, .{});
            module.addSystemFrameworkPath(.{ .cwd_relative = sdk ++ "/System/Library/Frameworks" });
            module.addSystemIncludePath(.{ .cwd_relative = sdk ++ "/usr/include" });
            module.addLibraryPath(.{ .cwd_relative = sdk ++ "/usr/lib" });
        },
    }
    if (options.unfiltered_closure) switch (root) {
        .update, .bmc, .plugin_fixture => {},
        .builtin_records, .compaction_e2e, .ai_gateway => {
            module.addImport("ui", zenit_dep.module("ui"));
            module.addImport("zenit_app", zenit_dep.module("zenit_app"));
            module.addImport("icon_ir", zenit_dep.module("icon_ir"));
            module.addImport("generated_ssh_session", ctx.ssh_session_translate.createModule());
            module.addImport("generated_ssh_channel", ctx.ssh_channel_translate.createModule());
            if (root != .builtin_records) module.addImport("generated_ghostty_vt", ctx.ghostty_translate.createModule());
        },
    };
    return tests;
}
