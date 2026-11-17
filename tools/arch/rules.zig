//! `rules.zon` 的数据模型、路径 glob 匹配与分层判定。
//!
//! 工具不硬编码任何仓库路径：路径 → 层、具名模块 → 层、import 矩阵、
//! 标识符禁用序列、test_id 提取上下文全部来自 `rules.zon`。
const std = @import("std");

pub const Module = struct {
    name: []const u8,
    layer: []const u8,
};

pub const LayerRule = struct {
    /// 段级 glob：`*` 匹配段内任意字符，`**` 匹配零个或多个整段，
    /// `{feature}` 匹配一个整段并把“到该段为止的路径”记为 feature 键。
    pattern: []const u8,
    layer: []const u8,
    /// 过渡条目：只为当前（未搬迁）布局服务，P1 搬迁后删除。
    transitional: bool = false,
};

pub const Allow = struct {
    from: []const u8,
    to: []const []const u8,
};

pub const IdentRule = struct {
    name: []const u8,
    /// 命中这些 glob 的文件才检查该规则。
    files: []const []const u8,
    /// 禁用的 token 序列，`a.b.c` 表示 标识符 a、`.`、标识符 b、`.`、标识符 c。
    forbid: []const []const u8,
    /// `files` 里再排除的文件（glob）：预览、验收程序、测试支撑、test-mode 路由等不受该规则约束的入口。
    skip: []const []const u8 = &.{},
    /// 只算“读”：序列后面紧跟赋值 `=` 的写入不算（`node.meta.ownership.meta.test_id = "x"` 是命名，不是查找）。
    reads_only: bool = false,
    /// 违规目标带上所在函数名（`seq @ fnName`）：同一文件里另一处新增的写法不会被已有的基线条目吞掉。
    per_function: bool = false,
};

/// 术语表护栏（docs/ui-revamp/GLOSSARY.md）：用户可见字符串里禁止出现的说法。
pub const TermRule = struct {
    /// 禁用词（UTF-8 子串，区分大小写）。
    term: []const u8,
    /// 应改用的说法（报告用）。
    use: []const u8,
};

/// 白名单：命中 `file` glob 的文件允许出现 `term`（必须写明理由）。
pub const TermAllow = struct {
    file: []const u8,
    term: []const u8,
    reason: []const u8,
};

pub const Terms = struct {
    /// 检查范围（glob）。
    files: []const []const u8 = &.{},
    /// 不检查的文件（预览、验收 runner 等不面向用户的入口）。
    skip: []const []const u8 = &.{},
    forbid: []const TermRule = &.{},
    allow: []const TermAllow = &.{},

    pub fn allowed(self: *const Terms, path: []const u8, term: []const u8) bool {
        for (self.allow) |entry| if (std.mem.eql(u8, entry.term, term) and matchGlob(entry.file, path) != null) return true;
        return false;
    }
};

pub const Rules = struct {
    /// 扫描的根目录（相对仓库根）。
    roots: []const []const u8,
    /// 参与扫描的扩展名。
    extensions: []const []const u8,
    /// 跳过的文件（glob）。生成物 `_*.yix.zig`、`_*.yss.zig` 在这里。
    skip: []const []const u8,
    /// 测试文件（glob）：整份文件按测试放宽。
    test_files: []const []const u8,
    modules: []const Module,
    /// 有序；第一个匹配的条目生效。
    layers: []const LayerRule,
    allow: []const Allow,
    /// 测试代码（测试文件与非测试文件里的 `test` 块）额外允许的目标层。
    /// 跨 feature 规则对测试代码照样生效。
    test_allow: []const []const u8,
    /// 目标属于另一个 feature 时，只允许这些层（门面）。
    cross_feature_allowed: []const []const u8,
    /// 这些来源层不受跨 feature 规则约束（聚合根、入口）。
    cross_feature_exempt: []const []const u8,
    idents: []const IdentRule,
    test_ids: TestIdRules,
    terms: Terms = .{},
    /// 快捷键文字护栏（一致性审查 #9，shortcuts 包）：视图与宿主的用户可见字符串里不许手写修饰键符号，
    /// 快捷键文字一律从 `shortcut_router` 取。结构同 `terms`（`term` 是禁用的符号，`use` 是应改用的来源）。
    shortcut_text: Terms = .{},
};

pub const TestIdRules = struct {
    /// 出现这些标识符的表达式里的字符串字面量视为“确定的 test_id 定义点”。
    contexts: []const []const u8,
    /// 以这些后缀结尾的字面量不是 id（文件名等）。
    exclude_suffixes: []const []const u8,
    /// e2e 扫描的目录与扩展名。
    e2e_dirs: []const []const u8,
    e2e_extensions: []const []const u8,
};

pub fn parse(gpa: std.mem.Allocator, arena: std.mem.Allocator, source: [:0]const u8, path: []const u8) !Rules {
    var diagnostics: std.zon.parse.Diagnostics = undefined;
    return std.zon.parse.fromSlice(Rules, .{
        .gpa = gpa,
        .arena = arena,
        .source = source,
        .diagnostics = &diagnostics,
    }) catch |err| {
        if (err == error.ParseZon) diagnostics.log(path);
        return err;
    };
}

// ── glob ─────────────────────────────────────────────────────────────

const max_segments = 64;

const Segments = struct {
    starts: [max_segments]usize = undefined,
    ends: [max_segments]usize = undefined,
    len: usize = 0,

    fn of(path: []const u8) ?Segments {
        var s: Segments = .{};
        var i: usize = 0;
        while (i <= path.len) {
            const end = std.mem.indexOfScalarPos(u8, path, i, '/') orelse path.len;
            if (end > i) {
                if (s.len == max_segments) return null;
                s.starts[s.len] = i;
                s.ends[s.len] = end;
                s.len += 1;
            }
            i = end + 1;
        }
        return s;
    }

    fn get(s: *const Segments, text: []const u8, i: usize) []const u8 {
        return text[s.starts[i]..s.ends[i]];
    }
};

/// 段内通配：只支持 `*`。
pub fn matchSegment(pattern: []const u8, text: []const u8) bool {
    var p: usize = 0;
    var t: usize = 0;
    var star: ?usize = null;
    var mark: usize = 0;
    while (t < text.len) {
        if (p < pattern.len and pattern[p] != '*' and pattern[p] == text[t]) {
            p += 1;
            t += 1;
        } else if (p < pattern.len and pattern[p] == '*') {
            star = p;
            p += 1;
            mark = t;
        } else if (star) |s| {
            p = s + 1;
            mark += 1;
            t = mark;
        } else return false;
    }
    while (p < pattern.len and pattern[p] == '*') p += 1;
    return p == pattern.len;
}

pub const Match = struct {
    /// `{feature}` 捕获：路径开头到 feature 段末尾，例如 `src/features/settings`。
    feature: ?[]const u8 = null,
};

pub fn matchGlob(pattern: []const u8, path: []const u8) ?Match {
    const ps = Segments.of(pattern) orelse return null;
    const ts = Segments.of(path) orelse return null;
    var m: Match = .{};
    if (matchFrom(pattern, &ps, 0, path, &ts, 0, &m)) return m;
    return null;
}

fn matchFrom(pattern: []const u8, ps: *const Segments, pi: usize, path: []const u8, ts: *const Segments, ti: usize, m: *Match) bool {
    if (pi == ps.len) return ti == ts.len;
    const seg = ps.get(pattern, pi);
    if (std.mem.eql(u8, seg, "**")) {
        var k = ti;
        while (k <= ts.len) : (k += 1) {
            if (matchFrom(pattern, ps, pi + 1, path, ts, k, m)) return true;
        }
        return false;
    }
    if (ti == ts.len) return false;
    if (std.mem.eql(u8, seg, "{feature}")) {
        if (matchFrom(pattern, ps, pi + 1, path, ts, ti + 1, m)) {
            m.feature = path[0..ts.ends[ti]];
            return true;
        }
        return false;
    }
    if (!matchSegment(seg, ts.get(path, ti))) return false;
    return matchFrom(pattern, ps, pi + 1, path, ts, ti + 1, m);
}

pub fn matchAny(patterns: []const []const u8, path: []const u8) bool {
    for (patterns) |p| if (matchGlob(p, path) != null) return true;
    return false;
}

// ── 分层 ─────────────────────────────────────────────────────────────

pub const Class = struct {
    layer: []const u8,
    feature: ?[]const u8 = null,
    transitional: bool = false,
};

pub fn classifyPath(rules: *const Rules, path: []const u8) ?Class {
    for (rules.layers) |entry| {
        if (matchGlob(entry.pattern, path)) |m| return .{ .layer = entry.layer, .feature = m.feature, .transitional = entry.transitional };
    }
    return null;
}

pub fn classifyModule(rules: *const Rules, name: []const u8) ?Class {
    for (rules.modules) |m| {
        if (std.mem.eql(u8, m.name, name)) return .{ .layer = m.layer };
    }
    return null;
}

pub fn contains(list: []const []const u8, item: []const u8) bool {
    for (list) |x| if (std.mem.eql(u8, x, item)) return true;
    return false;
}

pub fn allowed(rules: *const Rules, from: []const u8, to: []const u8, in_test: bool) bool {
    if (in_test and contains(rules.test_allow, to)) return true;
    for (rules.allow) |a| {
        if (std.mem.eql(u8, a.from, from)) return contains(a.to, to);
    }
    return false;
}

pub const Verdict = union(enum) {
    ok,
    /// 层矩阵不允许：规则名 `layer:<from>-><to>`。
    layer,
    /// 跨 feature 引用了非门面文件。
    cross_feature,
};

pub fn judge(rules: *const Rules, src: Class, dst: Class, in_test: bool) Verdict {
    if (!allowed(rules, src.layer, dst.layer, in_test)) return .layer;
    if (dst.feature) |df| {
        if (contains(rules.cross_feature_exempt, src.layer)) return .ok;
        const same = if (src.feature) |sf| std.mem.eql(u8, sf, df) else false;
        if (!same and !contains(rules.cross_feature_allowed, dst.layer)) return .cross_feature;
    }
    return .ok;
}

/// 返回所有被引用但没有 `allow` 条目的层名（规则文件自检）。
pub fn undefinedLayers(arena: std.mem.Allocator, rules: *const Rules) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (rules.layers) |l| try checkLayer(arena, rules, l.layer, &out);
    for (rules.modules) |m| try checkLayer(arena, rules, m.layer, &out);
    for (rules.allow) |a| for (a.to) |t| try checkLayer(arena, rules, t, &out);
    for (rules.test_allow) |t| try checkLayer(arena, rules, t, &out);
    return out.items;
}

fn checkLayer(arena: std.mem.Allocator, rules: *const Rules, layer: []const u8, out: *std.ArrayList([]const u8)) !void {
    for (rules.allow) |a| if (std.mem.eql(u8, a.from, layer)) return;
    if (contains(out.items, layer)) return;
    try out.append(arena, layer);
}

// ── 测试 ─────────────────────────────────────────────────────────────

const testing = std.testing;

test "glob: segment wildcard" {
    try testing.expect(matchSegment("*_tests.zig", "ai_tests.zig"));
    try testing.expect(matchSegment("settings_*", "settings_model.zig"));
    try testing.expect(matchSegment("*", "x"));
    try testing.expect(matchSegment("_*.yix.zig", "_card.yix.zig"));
    try testing.expect(!matchSegment("_*.yix.zig", "card.yix"));
    try testing.expect(!matchSegment("*_tests.zig", "ai_tests.zig.bak"));
    try testing.expect(matchSegment("a*b*c", "aXXbYYc"));
}

test "glob: double star and feature capture" {
    try testing.expect(matchGlob("src/**", "src/ui/a.zig") != null);
    try testing.expect(matchGlob("src/**", "src") != null);
    try testing.expect(matchGlob("src/*.zig", "src/ui/a.zig") == null);
    try testing.expect(matchGlob("**/_*.yss.zig", "src/ui/settings/_styles.yss.zig") != null);
    const m = matchGlob("src/features/{feature}/**/model/view_model.zig", "src/features/connections/wizard/model/view_model.zig").?;
    try testing.expectEqualStrings("src/features/connections", m.feature.?);
    try testing.expect(matchGlob("src/features/{feature}/**/model/**", "src/features/settings/view/x.zig") == null);
    const p = matchGlob("src/plugins/{feature}/**", "src/plugins/bmc_ikvm/protocol/http.zig").?;
    try testing.expectEqualStrings("src/plugins/bmc_ikvm", p.feature.?);
}

pub const embedded_rules = @embedFile("rules.zon");

pub fn loadEmbeddedForTest(arena: std.mem.Allocator) !Rules {
    return parse(testing.allocator, arena, embedded_rules, "rules.zon");
}

test "rules.zon parses and every referenced layer has an allow entry" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const rules = try loadEmbeddedForTest(arena_state.allocator());
    const missing = try undefinedLayers(arena_state.allocator(), &rules);
    if (missing.len != 0) {
        for (missing) |m| std.debug.print("layer without allow entry: {s}\n", .{m});
        return error.UndefinedLayer;
    }
}

fn expectLayer(rules: *const Rules, path: []const u8, layer: []const u8, feature: ?[]const u8) !void {
    const c = classifyPath(rules, path) orelse {
        std.debug.print("unclassified: {s}\n", .{path});
        return error.Unclassified;
    };
    testing.expectEqualStrings(layer, c.layer) catch |err| {
        std.debug.print("path {s}\n", .{path});
        return err;
    };
    if (feature) |f| try testing.expectEqualStrings(f, c.feature.?) else try testing.expect(c.feature == null);
}

test "layers: target layout (§5.1)" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const rules = try loadEmbeddedForTest(arena_state.allocator());
    try expectLayer(&rules, "src/main.zig", "entry", null);
    try expectLayer(&rules, "src/root.zig", "entry", null);
    try expectLayer(&rules, "src/tests_ui.zig", "entry", null);
    try expectLayer(&rules, "src/preview.zig", "entry", null);
    try expectLayer(&rules, "src/app/main_window.zig", "app", null);
    try expectLayer(&rules, "src/features/settings/mod.zig", "facade", "src/features/settings");
    try expectLayer(&rules, "src/features/settings/model/controller.zig", "model", "src/features/settings");
    try expectLayer(&rules, "src/features/settings/model/view_model.zig", "view_model", "src/features/settings");
    try expectLayer(&rules, "src/features/settings/view/settings_window.yix", "view", "src/features/settings");
    try expectLayer(&rules, "src/features/settings/view/styles.yss", "view", "src/features/settings");
    try expectLayer(&rules, "src/features/settings/view/components/theme_gallery/mod.zig", "view", "src/features/settings");
    try expectLayer(&rules, "src/features/settings/host/settings_host.zig", "host", "src/features/settings");
    try expectLayer(&rules, "src/features/settings/tests/controller_tests.zig", "tests", "src/features/settings");
    try expectLayer(&rules, "src/features/settings/preview.zig", "host", "src/features/settings");
    try expectLayer(&rules, "src/features/connections/wizard/model/state.zig", "model", "src/features/connections");
    try expectLayer(&rules, "src/features/connections/wizard/view/wizard.yix", "view", "src/features/connections");
    try expectLayer(&rules, "src/shared/ui/theme/app_theme.zig", "shared_ui", null);
    try expectLayer(&rules, "src/shared/base/strings.zig", "shared_base", null);
    try expectLayer(&rules, "src/shared/testing/ui_kit.zig", "shared_testing", null);
    try expectLayer(&rules, "src/platform/keychain.zig", "platform", null);
    for ([_][]const u8{ "proto", "vt", "transfer", "local", "host", "ai", "config", "update" }) |dir| {
        const p = try std.fmt.allocPrint(arena_state.allocator(), "src/{s}/x.zig", .{dir});
        try expectLayer(&rules, p, "core", null);
    }
    try expectLayer(&rules, "src/plugins/bmc_ikvm/mod.zig", "facade", "src/plugins/bmc_ikvm");
    try expectLayer(&rules, "src/plugins/bmc_ikvm/model/state.zig", "model", "src/plugins/bmc_ikvm");
    try expectLayer(&rules, "src/plugins/bmc_ikvm/view/kvm.yix", "view", "src/plugins/bmc_ikvm");
    try expectLayer(&rules, "src/plugins/bmc_ikvm/host/x_host.zig", "host", "src/plugins/bmc_ikvm");
    // P1 move-map 实际用到的位置：子域、预览与验收 runner、跨 feature 测试、core 目录里的 tests/acceptance
    try expectLayer(&rules, "src/tests_local.zig", "entry", null);
    try expectLayer(&rules, "src/acceptance.zig", "entry", null);
    try expectLayer(&rules, "src/features/ai/cards/view/ai_step_view.zig", "view", "src/features/ai");
    try expectLayer(&rules, "src/features/ai/cards/preview/task_finish_preview_runner.zig", "runner", "src/features/ai");
    try expectLayer(&rules, "src/features/settings/preview/settings_preview_runner.zig", "runner", "src/features/settings");
    try expectLayer(&rules, "src/features/workspace/tests/acceptance/ssh_disconnect_runner.zig", "runner", "src/features/workspace");
    try expectLayer(&rules, "src/features/workspace/tests/ssh_reconnect_tests.zig", "tests", "src/features/workspace");
    try expectLayer(&rules, "src/shared/ui/tests/theme_layer_tests.zig", "shared_ui_tests", null);
    try expectLayer(&rules, "src/shared/ui/preview/button_policy_preview_runner.zig", "shared_ui_tests", null);
    try expectLayer(&rules, "src/shared/ui/components/copy_button/copy_button.zig", "shared_ui", null);
    try expectLayer(&rules, "src/plugins/bmc_ikvm/preview/bmc_kvm_preview_runner.zig", "runner", "src/plugins/bmc_ikvm");
    try expectLayer(&rules, "src/plugins/bmc_ikvm/acceptance/bmc_live_readonly_runner.zig", "runner", "src/plugins/bmc_ikvm");
    try expectLayer(&rules, "src/plugins/bmc_ikvm/tests/bmc_rfb_tests.zig", "tests", "src/plugins/bmc_ikvm");
    try expectLayer(&rules, "src/proto/ssh/acceptance/fixed_forward_runner.zig", "runner", null);
    try expectLayer(&rules, "src/platform/acceptance/application_environment_contract.zig", "runner", null);
    try expectLayer(&rules, "src/vt/acceptance/vt_conformance_runner.zig", "runner", null);
    try expectLayer(&rules, "src/host/tests/record_cleanup_tests.zig", "core", null);
    try expectLayer(&rules, "src/platform/tests/applog_tests.zig", "platform", null);
    try testing.expect(matchAny(rules.test_files, "src/host/tests/support.zig"));
    try testing.expect(matchAny(rules.test_files, "src/features/connections/wizard/tests/fixture.zig"));
}

test "layers: plugins transitional layout (P5)" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const rules = try loadEmbeddedForTest(arena_state.allocator());
    try expectLayer(&rules, "src/plugins/linked_plugins.zig", "plugin_registry", null);
    try expectLayer(&rules, "src/plugins/bmc_ikvm/non_ui.zig", "facade", "src/plugins/bmc_ikvm");
    try expectLayer(&rules, "src/plugins/bmc_ikvm/plugin.zig", "facade", "src/plugins/bmc_ikvm");
    try expectLayer(&rules, "src/plugins/bmc_ikvm/views.zig", "legacy_plugin", "src/plugins/bmc_ikvm");
    try expectLayer(&rules, "src/plugins/bmc_ikvm/protocol/http.zig", "legacy_plugin", "src/plugins/bmc_ikvm");
    // P1 之后旧布局不再有任何条目
    try testing.expect(classifyPath(&rules, "src/ui/workspace.zig") == null);
    try testing.expect(classifyPath(&rules, "src/transfer_panel_tests.zig") == null);
    try testing.expect(classifyPath(&rules, "vendor/zenit/src/ui.zig") == null);
    try testing.expect(matchAny(rules.skip, "src/features/settings/view/_styles.yss.zig"));
    try testing.expect(matchAny(rules.skip, "src/features/x/view/_a.yix.zig"));
    try testing.expect(!matchAny(rules.skip, "src/features/settings/view/styles.zig"));
    try testing.expect(matchAny(rules.test_files, "src/features/a/view/foo_tests.zig"));
    try testing.expect(matchAny(rules.test_files, "src/features/a/tests/all.zig"));
}

fn verdictOf(rules: *const Rules, src: []const u8, dst: []const u8, in_test: bool) !Verdict {
    const s = classifyPath(rules, src) orelse return error.Unclassified;
    const d = classifyPath(rules, dst) orelse classifyModule(rules, dst) orelse return error.Unclassified;
    return judge(rules, s, d, in_test);
}

test "matrix: §4.2 target layout" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const rules = try loadEmbeddedForTest(arena_state.allocator());
    const r = &rules;
    // core
    try testing.expectEqual(Verdict.layer, try verdictOf(r, "src/host/a.zig", "ui", false));
    try testing.expectEqual(Verdict.ok, try verdictOf(r, "src/host/a.zig", "std", false));
    try testing.expectEqual(Verdict.ok, try verdictOf(r, "src/host/a.zig", "src/platform/keychain.zig", false));
    try testing.expectEqual(Verdict.ok, try verdictOf(r, "src/host/a.zig", "src/vt/b.zig", false));
    try testing.expectEqual(Verdict.layer, try verdictOf(r, "src/host/a.zig", "src/features/settings/mod.zig", false));
    try testing.expectEqual(Verdict.layer, try verdictOf(r, "src/host/a.zig", "src/shared/ui/theme/app_theme.zig", false));
    try testing.expectEqual(Verdict.ok, try verdictOf(r, "src/host/a.zig", "src/shared/base/s.zig", false));
    // model
    const m = "src/features/settings/model/controller.zig";
    try testing.expectEqual(Verdict.layer, try verdictOf(r, m, "ui", false));
    try testing.expectEqual(Verdict.ok, try verdictOf(r, m, "src/config/config.zig", false));
    try testing.expectEqual(Verdict.layer, try verdictOf(r, m, "src/platform/keychain.zig", false));
    try testing.expectEqual(Verdict.layer, try verdictOf(r, m, "src/features/settings/view/x.zig", false));
    try testing.expectEqual(Verdict.layer, try verdictOf(r, m, "src/features/settings/host/x.zig", false));
    try testing.expectEqual(Verdict.ok, try verdictOf(r, m, "src/features/settings/model/state.zig", false));
    try testing.expectEqual(Verdict.ok, try verdictOf(r, m, "src/features/ai/mod.zig", false));
    try testing.expectEqual(Verdict.cross_feature, try verdictOf(r, m, "src/features/ai/model/state.zig", false));
    // view_model：可以 import ui（具体子集由标识符规则管）
    try testing.expectEqual(Verdict.ok, try verdictOf(r, "src/features/settings/model/view_model.zig", "ui", false));
    // view
    const v = "src/features/settings/view/nav.yix";
    try testing.expectEqual(Verdict.ok, try verdictOf(r, v, "ui", false));
    try testing.expectEqual(Verdict.layer, try verdictOf(r, v, "src/platform/keychain.zig", false));
    try testing.expectEqual(Verdict.layer, try verdictOf(r, v, "src/config/config.zig", false));
    try testing.expectEqual(Verdict.ok, try verdictOf(r, v, "src/features/settings/model/view_model.zig", false));
    try testing.expectEqual(Verdict.ok, try verdictOf(r, v, "src/shared/ui/components/x/mod.zig", false));
    try testing.expectEqual(Verdict.layer, try verdictOf(r, v, "src/features/settings/host/settings_host.zig", false));
    try testing.expectEqual(Verdict.cross_feature, try verdictOf(r, v, "src/features/ai/view/x.zig", false));
    // host
    const h = "src/features/settings/host/settings_host.zig";
    try testing.expectEqual(Verdict.ok, try verdictOf(r, h, "src/platform/keychain.zig", false));
    try testing.expectEqual(Verdict.ok, try verdictOf(r, h, "src/config/config.zig", false));
    try testing.expectEqual(Verdict.ok, try verdictOf(r, h, "src/features/settings/view/x.zig", false));
    try testing.expectEqual(Verdict.layer, try verdictOf(r, h, "src/app/main_window.zig", false));
    try testing.expectEqual(Verdict.cross_feature, try verdictOf(r, h, "src/features/ai/host/ai_host.zig", false));
    // shared/ui
    try testing.expectEqual(Verdict.layer, try verdictOf(r, "src/shared/ui/a.zig", "src/config/config.zig", false));
    try testing.expectEqual(Verdict.layer, try verdictOf(r, "src/shared/ui/a.zig", "src/features/ai/mod.zig", false));
    try testing.expectEqual(Verdict.ok, try verdictOf(r, "src/shared/ui/a.zig", "ui", false));
    // app
    try testing.expectEqual(Verdict.ok, try verdictOf(r, "src/app/main.zig", "src/features/ai/mod.zig", false));
    try testing.expectEqual(Verdict.cross_feature, try verdictOf(r, "src/app/main.zig", "src/features/ai/host/ai_host.zig", false));
    // 门面不受跨 feature 限制
    try testing.expectEqual(Verdict.ok, try verdictOf(r, "src/features/ai/view/a.zig", "src/features/settings/mod.zig", false));
    // plugins 当作 feature
    try testing.expectEqual(Verdict.cross_feature, try verdictOf(r, "src/plugins/bmc_ikvm/view/a.zig", "src/plugins/fixture_probe/model/x.zig", false));
    // 预览/验收 runner：程序入口性质，但仍受跨 feature 限制
    const pr = "src/features/ai/cards/preview/task_finish_preview_runner.zig";
    try testing.expectEqual(Verdict.ok, try verdictOf(r, pr, "zenit_app", false));
    try testing.expectEqual(Verdict.ok, try verdictOf(r, pr, "ui_font_assets", false));
    try testing.expectEqual(Verdict.ok, try verdictOf(r, pr, "src/features/ai/cards/host/x.zig", false));
    try testing.expectEqual(Verdict.ok, try verdictOf(r, pr, "src/shared/testing/ui_kit.zig", false));
    try testing.expectEqual(Verdict.cross_feature, try verdictOf(r, pr, "src/features/transfer/view/x.zig", false));
    try testing.expectEqual(Verdict.layer, try verdictOf(r, pr, "src/app/main_window.zig", false));
    try testing.expectEqual(Verdict.ok, try verdictOf(r, "src/proto/ssh/acceptance/fixed_forward_runner.zig", "src/platform/keychain.zig", false));
    try testing.expectEqual(Verdict.cross_feature, try verdictOf(r, "src/host/acceptance/x_runner.zig", "src/features/ai/host/x.zig", false));
    // shared/ui 的跨 feature 测试不受跨 feature 限制，但普通 shared/ui 仍不能 import feature
    try testing.expectEqual(Verdict.ok, try verdictOf(r, "src/shared/ui/tests/theme_layer_tests.zig", "src/features/ai/view/x.zig", false));
    try testing.expectEqual(Verdict.layer, try verdictOf(r, "src/shared/ui/theme/app_theme.zig", "src/features/ai/view/x.zig", false));
    // 入口与聚合根可以 import runner 与 shared/ui 测试
    try testing.expectEqual(Verdict.ok, try verdictOf(r, "src/preview.zig", pr, false));
    try testing.expectEqual(Verdict.ok, try verdictOf(r, "src/tests_ui.zig", "src/shared/ui/tests/theme_layer_tests.zig", false));
}

test "matrix: test relaxation (§4.2 补充规则)" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const rules = try loadEmbeddedForTest(arena_state.allocator());
    const r = &rules;
    const t = "src/features/settings/tests/controller_tests.zig";
    try testing.expectEqual(Verdict.ok, try verdictOf(r, t, "src/features/settings/host/settings_host.zig", false));
    try testing.expectEqual(Verdict.ok, try verdictOf(r, t, "src/shared/testing/ui_kit.zig", false));
    try testing.expectEqual(Verdict.ok, try verdictOf(r, t, "src/config/config.zig", false));
    try testing.expectEqual(Verdict.cross_feature, try verdictOf(r, t, "src/features/ai/model/state.zig", false));
    // 测试代码（测试文件由调用方按 test_files 传 in_test）可以 import platform（§4.2 对测试放宽）；非测试代码的 view 仍不行
    try testing.expectEqual(Verdict.ok, try verdictOf(r, t, "src/platform/keychain.zig", true));
    try testing.expectEqual(Verdict.ok, try verdictOf(r, "src/features/settings/view/a.zig", "src/platform/keychain.zig", true));
    try testing.expectEqual(Verdict.layer, try verdictOf(r, "src/features/settings/view/a.zig", "src/platform/keychain.zig", false));
    // 插件尚未分层（P5）：插件自己的 tests/ 与 runner 可以 import 本插件内部文件，跨插件仍不行
    try testing.expectEqual(Verdict.ok, try verdictOf(r, "src/plugins/bmc_ikvm/tests/bmc_tests.zig", "src/plugins/bmc_ikvm/views.zig", false));
    try testing.expectEqual(Verdict.ok, try verdictOf(r, "src/plugins/bmc_ikvm/preview/bmc_preview_runner.zig", "src/plugins/bmc_ikvm/views.zig", false));
    try testing.expectEqual(Verdict.cross_feature, try verdictOf(r, "src/plugins/bmc_ikvm/tests/bmc_tests.zig", "src/plugins/fixture_probe/model.zig", false));
    // 非测试文件中的 test 块：model 里的 test 块可以 import 本 feature 的 view/host 与 shared/testing
    const m = "src/features/settings/model/controller.zig";
    try testing.expectEqual(Verdict.layer, try verdictOf(r, m, "src/shared/testing/ui_kit.zig", false));
    try testing.expectEqual(Verdict.ok, try verdictOf(r, m, "src/shared/testing/ui_kit.zig", true));
    try testing.expectEqual(Verdict.ok, try verdictOf(r, m, "src/features/settings/host/x.zig", true));
    try testing.expectEqual(Verdict.cross_feature, try verdictOf(r, m, "src/features/ai/host/x.zig", true));
    // core 的 test 块可以 import shared/testing
    try testing.expectEqual(Verdict.ok, try verdictOf(r, "src/config/a.zig", "src/shared/testing/data_directory.zig", true));
    try testing.expectEqual(Verdict.layer, try verdictOf(r, "src/config/a.zig", "src/shared/testing/data_directory.zig", false));
}

test "matrix: plugins transitional layout (P5)" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const rules = try loadEmbeddedForTest(arena_state.allocator());
    const r = &rules;
    try testing.expectEqual(Verdict.ok, try verdictOf(r, "src/main.zig", "src/plugins/bmc_ikvm/views.zig", false));
    try testing.expectEqual(Verdict.ok, try verdictOf(r, "src/tests_bmc.zig", "src/plugins/bmc_ikvm/views.zig", false));
    try testing.expectEqual(Verdict.layer, try verdictOf(r, "src/features/workspace/view/workspace.zig", "src/plugins/bmc_ikvm/views.zig", false));
    try testing.expectEqual(Verdict.ok, try verdictOf(r, "src/features/workspace/view/workspace.zig", "src/plugins/bmc_ikvm/non_ui.zig", false));
    try testing.expectEqual(Verdict.layer, try verdictOf(r, "src/plugins/bmc_ikvm/views.zig", "src/features/workspace/view/workspace.zig", false));
    try testing.expectEqual(Verdict.ok, try verdictOf(r, "src/plugins/bmc_ikvm/views.zig", "src/shared/ui/theme/app_theme.zig", false));
    try testing.expectEqual(Verdict.cross_feature, try verdictOf(r, "src/plugins/bmc_ikvm/views.zig", "src/plugins/fixture_probe/model.zig", false));
    try testing.expectEqual(Verdict.ok, try verdictOf(r, "src/plugins/bmc_ikvm/views.zig", "src/plugins/bmc_ikvm/model.zig", false));
    try testing.expectEqual(Verdict.layer, try verdictOf(r, "src/host/session_host.zig", "src/plugins/linked_plugins.zig", false));
    try testing.expectEqual(Verdict.ok, try verdictOf(r, "src/plugins/application_plugins.zig", "src/plugins/bmc_ikvm/plugin.zig", false));
    try testing.expectEqual(Verdict.cross_feature, try verdictOf(r, "src/plugins/application_plugins.zig", "src/plugins/bmc_ikvm/management_journal.zig", false));
    try testing.expectEqual(Verdict.layer, try verdictOf(r, "src/platform/a.zig", "src/config/config.zig", false));
    try testing.expectEqual(Verdict.layer, try verdictOf(r, "src/host/file_workspace_controller.zig", "src/features/files/view/file_workspace_view.zig", false));
    try testing.expectEqual(Verdict.layer, try verdictOf(r, "src/config/transfer_defaults.zig", "src/shared/ui/theme/app_theme.zig", false));
    try testing.expectEqual(Verdict.ok, try verdictOf(r, "src/features/a/view/a_tests.zig", "src/shared/testing/data_directory.zig", true));
}
