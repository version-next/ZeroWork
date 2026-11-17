//! test_id 提取：源码中的 id 定义点（§6.3 第 1 条）与 e2e 交叉引用（第 2 条）。
//!
//! 规则（详见 README）：
//! - 候选字面量：形如 `a.b[.c…]` 的点分小写字符串（段为 `[a-z0-9_-]`，首段以字母开头）。
//!   含 `{` 的格式串取 `{` 之前的部分；以 `.` 结尾的视为前缀，记作 `prefix:<…>.`。
//! - 第一遍：`rules.zon` 中 `test_ids.contexts`（`test_id`、`testId`、`stableId`）之后、
//!   同一表达式内的候选字面量是“确定定义点”，由此得到一级前缀集合。
//! - 第二遍：非测试代码中任何候选字面量，只要一级前缀在集合中，也收入（宁多勿漏：
//!   覆盖经数组 / 参数间接传给 test_id 的 id）。
//! - 测试文件与 `test` 块内的字面量不收（多为断言用的具体化动态 id）。
const std = @import("std");
const scan = @import("scan.zig");

pub const Candidate = struct {
    /// 完整 id，或前缀（以 `.` 结尾）。
    value: []const u8,
    prefix: bool,

    pub fn key(c: Candidate, arena: std.mem.Allocator) ![]const u8 {
        return if (c.prefix) std.fmt.allocPrint(arena, "prefix:{s}", .{c.value}) else c.value;
    }

    pub fn root(c: Candidate) []const u8 {
        const idx = std.mem.indexOfScalar(u8, c.value, '.') orelse return c.value;
        return c.value[0..idx];
    }
};

fn isSegChar(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or (ch >= '0' and ch <= '9') or ch == '_' or ch == '-';
}

/// `a.b.c` 是否是 id 形状（至少两段）。
pub fn isIdShape(s: []const u8) bool {
    if (s.len < 3) return false;
    if (!(s[0] >= 'a' and s[0] <= 'z')) return false;
    var segments: usize = 1;
    var seg_len: usize = 0;
    for (s) |ch| {
        if (ch == '.') {
            if (seg_len == 0) return false;
            segments += 1;
            seg_len = 0;
        } else if (isSegChar(ch)) {
            seg_len += 1;
        } else return false;
    }
    return seg_len > 0 and segments >= 2;
}

/// 前缀形状：`a.` 或 `a.b.`（至少一段，以 `.` 结尾）。
fn isPrefixShape(s: []const u8) bool {
    if (s.len < 2 or s[s.len - 1] != '.') return false;
    const body = s[0 .. s.len - 1];
    if (!(body[0] >= 'a' and body[0] <= 'z')) return false;
    var seg_len: usize = 0;
    for (body) |ch| {
        if (ch == '.') {
            if (seg_len == 0) return false;
            seg_len = 0;
        } else if (isSegChar(ch)) {
            seg_len += 1;
        } else return false;
    }
    return seg_len > 0;
}

/// 把一个字符串字面量的内容归类为 id / 前缀候选。
/// `cut_at`：格式串 / 模板串的插值起点（Zig `{`、TS `${`）。
pub fn classify(value: []const u8, exclude_suffixes: []const []const u8) ?Candidate {
    var v = value;
    var templated = false;
    if (std.mem.indexOfScalar(u8, v, '{')) |idx| {
        v = v[0..idx];
        templated = true;
        if (std.mem.endsWith(u8, v, "$")) v = v[0 .. v.len - 1];
    }
    for (exclude_suffixes) |suffix| if (std.mem.endsWith(u8, v, suffix)) return null;
    if (isPrefixShape(v)) return .{ .value = v, .prefix = true };
    if (templated) {
        // `"ai.child.{s}"` 之外的写法，例如 `"ai.row{d}"`：退到最后一个 `.`。
        const dot = std.mem.lastIndexOfScalar(u8, v, '.') orelse return null;
        const p = v[0 .. dot + 1];
        if (isPrefixShape(p)) return .{ .value = p, .prefix = true };
        return null;
    }
    if (isIdShape(v)) return .{ .value = v, .prefix = false };
    return null;
}

pub const Collector = struct {
    arena: std.mem.Allocator,
    exclude_suffixes: []const []const u8,
    contexts: []const []const u8,
    /// 确定定义点
    definite: std.StringArrayHashMapUnmanaged(Candidate) = .empty,
    /// 第二遍的候选（非测试代码中的全部候选字面量）
    loose: std.StringArrayHashMapUnmanaged(Candidate) = .empty,
    /// 测试代码中的候选字面量（只统计，不进基线）
    test_only: std.StringArrayHashMapUnmanaged(void) = .empty,
    /// 非测试代码里“占位符之后还有字面量”的格式串（`wizard.{s}.error` → `wizard.*.error`）。
    /// 不进基线，只供 e2e 悬空检查核对运行期拼接的 id（见 `SourceIndex`）。
    patterns: std.StringArrayHashMapUnmanaged(void) = .empty,
    /// 非测试代码里的后缀字面量（`".popover"`、`".header"`）：部件 id 常由“已有 id ++ 后缀”拼成
    /// （`scopedId(scope, id, ".popover")`、`id ++ ".header"`）。同样只供 e2e 悬空检查使用。
    suffixes: std.StringArrayHashMapUnmanaged(void) = .empty,

    /// 扫描一个源文件。`whole_file_is_test` 为真时整份文件按测试代码处理。
    pub fn addSource(self: *Collector, source: []const u8, toks: []const scan.Tok, whole_file_is_test: bool) !void {
        var i: usize = 0;
        while (i < toks.len) : (i += 1) {
            const t = toks[i];
            const in_test = whole_file_is_test or t.in_test;
            if (t.tag == .identifier and isContext(self, scan.text(source, t))) {
                const is_decl = i > 0 and toks[i - 1].tag == .keyword_fn;
                if (!in_test and !is_decl) try self.collectExpression(source, toks, i + 1);
                continue;
            }
            if (t.tag != .string_literal) continue;
            const value = scan.stringValue(self.arena, source, t) orelse continue;
            if (!in_test) if (try globOf(self.arena, value)) |g| try self.patterns.put(self.arena, g, {});
            if (!in_test and isSuffixShape(value, self.exclude_suffixes)) try self.suffixes.put(self.arena, value, {});
            const c = classify(value, self.exclude_suffixes) orelse continue;
            const k = try c.key(self.arena);
            if (in_test) {
                try self.test_only.put(self.arena, k, {});
            } else {
                try self.loose.put(self.arena, k, c);
            }
        }
    }

    fn isContext(self: *Collector, name: []const u8) bool {
        for (self.contexts) |c| if (std.mem.eql(u8, c, name)) return true;
        return false;
    }

    /// 从上下文标识符之后开始，收集同一表达式内的候选字面量：
    /// 到深度 0 的 `;` / `,` 或深度降到 0 以下为止。
    fn collectExpression(self: *Collector, source: []const u8, toks: []const scan.Tok, start: usize) !void {
        var depth: isize = 0;
        var j = start;
        while (j < toks.len) : (j += 1) {
            const t = toks[j];
            if (t.tag == .l_brace and depth == 0 and j > 0 and toks[j - 1].tag != .period) return;
            switch (t.tag) {
                .l_paren, .l_brace, .l_bracket => depth += 1,
                .r_paren, .r_brace, .r_bracket => {
                    depth -= 1;
                    if (depth < 0) return;
                },
                .semicolon => if (depth <= 0) return,
                .comma => if (depth <= 0) return,
                .string_literal => {
                    const value = scan.stringValue(self.arena, source, t) orelse continue;
                    const c = classify(value, self.exclude_suffixes) orelse continue;
                    try self.definite.put(self.arena, try c.key(self.arena), c);
                },
                else => {},
            }
        }
    }

    /// 合并两遍的结果：确定定义点 + 一级前缀在确定集合中的松散候选。
    pub fn finish(self: *Collector) ![]const []const u8 {
        var roots: std.StringHashMapUnmanaged(void) = .empty;
        for (self.definite.values()) |c| try roots.put(self.arena, c.root(), {});
        var out: std.StringArrayHashMapUnmanaged(void) = .empty;
        for (self.definite.keys()) |k| try out.put(self.arena, k, {});
        for (self.loose.keys(), self.loose.values()) |k, c| {
            if (roots.contains(c.root())) try out.put(self.arena, k, {});
        }
        const keys = try self.arena.dupe([]const u8, out.keys());
        sortStrings(keys);
        return keys;
    }

    /// 格式串通配（一级前缀在确定定义点集合里的那些），排序。`finish` 之后调用。
    pub fn finishPatterns(self: *Collector) ![]const []const u8 {
        var roots: std.StringHashMapUnmanaged(void) = .empty;
        for (self.definite.values()) |c| try roots.put(self.arena, c.root(), {});
        var out: std.ArrayList([]const u8) = .empty;
        for (self.patterns.keys()) |g| {
            const dot = std.mem.indexOfScalar(u8, g, '.') orelse continue;
            if (roots.contains(g[0..dot])) try out.append(self.arena, g);
        }
        sortStrings(out.items);
        return out.items;
    }
};

/// 后缀形状：`.a` 或 `.a.b`（以 `.` 开头，段为 id 字符），且不是文件扩展名之类的排除后缀。
pub fn isSuffixShape(value: []const u8, exclude_suffixes: []const []const u8) bool {
    if (value.len < 2 or value[0] != '.') return false;
    var seg_len: usize = 0;
    for (value[1..]) |ch| {
        if (ch == '.') {
            if (seg_len == 0) return false;
            seg_len = 0;
        } else if (isSegChar(ch)) {
            seg_len += 1;
        } else return false;
    }
    if (seg_len == 0) return false;
    for (exclude_suffixes) |suffix| if (std.mem.eql(u8, value, suffix)) return false;
    return true;
}

/// Zig 格式串 → 通配：每个 `{…}` 换成 `*`。只收“占位符后面还有字面量”的 id 形状
/// （`wizard.{s}.error`、`tabs.tab.{d}.close`）；以占位符结尾的由前缀规则处理。
pub fn globOf(arena: std.mem.Allocator, value: []const u8) !?[]const u8 {
    if (std.mem.indexOfScalar(u8, value, '{') == null) return null;
    var buf: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < value.len) : (i += 1) {
        const ch = value[i];
        if (ch == '{') {
            const close = std.mem.indexOfScalarPos(u8, value, i, '}') orelse return null;
            if (buf.items.len == 0 or buf.items[buf.items.len - 1] != '*') try buf.append(arena, '*');
            i = close;
        } else if (isSegChar(ch) or ch == '.') {
            try buf.append(arena, ch);
        } else return null;
    }
    const g = buf.items;
    if (g.len < 3 or g[g.len - 1] == '*' or g[g.len - 1] == '.') return null;
    if (!(g[0] >= 'a' and g[0] <= 'z') or std.mem.indexOfScalar(u8, g, '.') == null) return null;
    if (std.mem.indexOf(u8, g, "..") != null) return null;
    return g;
}

/// `*` 匹配一个或多个 id 字符（含 `.`：`{s}` 可以展开成多段）。
pub fn globMatch(glob: []const u8, text: []const u8) bool {
    if (glob.len == 0) return text.len == 0;
    if (glob[0] == '*') {
        var n: usize = 1;
        while (n <= text.len) : (n += 1) {
            if (globMatch(glob[1..], text[n..])) return true;
        }
        return false;
    }
    return text.len > 0 and glob[0] == text[0] and globMatch(glob[1..], text[1..]);
}

pub fn sortStrings(items: [][]const u8) void {
    std.mem.sort([]const u8, items, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lt);
}

// ── e2e（TS/MTS）字符串扫描 ─────────────────────────────────────────

/// 提取 TS 源码里 `'…'`、`"…"`、`` `…` `` 字符串的内容（模板串截到第一个 `${`）。
/// 跳过 `//` 与 `/* */` 注释；不处理正则字面量（误报只会让清单变大）。
pub fn scriptStrings(arena: std.mem.Allocator, source: []const u8) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var i: usize = 0;
    while (i < source.len) {
        const ch = source[i];
        if (ch == '/' and i + 1 < source.len and source[i + 1] == '/') {
            i = std.mem.indexOfScalarPos(u8, source, i, '\n') orelse source.len;
            continue;
        }
        if (ch == '/' and i + 1 < source.len and source[i + 1] == '*') {
            i = if (std.mem.indexOfPos(u8, source, i + 2, "*/")) |e| e + 2 else source.len;
            continue;
        }
        if (ch == '\'' or ch == '"' or ch == '`') {
            var buf: std.ArrayList(u8) = .empty;
            var j = i + 1;
            var cut = false;
            while (j < source.len and source[j] != ch) : (j += 1) {
                if (source[j] == '\\' and j + 1 < source.len) {
                    j += 1;
                    if (!cut) try buf.append(arena, source[j]);
                    continue;
                }
                if (ch != '`' and source[j] == '\n') break;
                if (ch == '`' and source[j] == '$' and j + 1 < source.len and source[j + 1] == '{') {
                    if (!cut) try buf.appendSlice(arena, "${");
                    cut = true;
                    // 跳过插值表达式（可能含引号）
                    var depth: usize = 0;
                    j += 1;
                    while (j < source.len) : (j += 1) {
                        if (source[j] == '{') depth += 1;
                        if (source[j] == '}') {
                            depth -= 1;
                            if (depth == 0) break;
                        }
                    }
                    continue;
                }
                if (!cut) try buf.append(arena, source[j]);
            }
            try out.append(arena, buf.items);
            i = j + 1;
            continue;
        }
        i += 1;
    }
    return out.items;
}

pub const E2eUse = struct {
    /// e2e 中出现、且命中源码清单的条目（源码清单里的 key）
    used: []const []const u8,
    /// e2e 中形似 id 但源码清单未覆盖的字符串数量（含误报与运行期拼接的 id）
    unmatched: usize,
    candidates: usize,
};

/// 把 e2e 字符串与源码清单求交。
/// - 完全相等的 id → 该 id；
/// - e2e 的 id 或前缀以源码前缀开头 → 该源码前缀；
pub fn crossReference(arena: std.mem.Allocator, source_keys: []const []const u8, e2e_strings: []const []const u8, exclude_suffixes: []const []const u8) !E2eUse {
    var exact: std.StringHashMapUnmanaged(void) = .empty;
    var prefixes: std.ArrayList([]const u8) = .empty;
    for (source_keys) |k| {
        if (std.mem.startsWith(u8, k, "prefix:")) try prefixes.append(arena, k["prefix:".len..]) else try exact.put(arena, k, {});
    }
    var used: std.StringArrayHashMapUnmanaged(void) = .empty;
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    var unmatched: usize = 0;
    for (e2e_strings) |s| {
        const c = classify(s, exclude_suffixes) orelse continue;
        if ((try seen.getOrPut(arena, try c.key(arena))).found_existing) continue;
        if (!c.prefix and exact.contains(c.value)) {
            try used.put(arena, c.value, {});
            continue;
        }
        // 未精确命中：只标记最长的匹配前缀（避免 `ai.` 这类宽前缀吞掉一切）。
        var best: ?[]const u8 = null;
        for (prefixes.items) |p| {
            if (std.mem.startsWith(u8, c.value, p) and (best == null or p.len > best.?.len)) best = p;
        }
        if (best) |p| {
            try used.put(arena, try std.fmt.allocPrint(arena, "prefix:{s}", .{p}), {});
        } else unmatched += 1;
    }
    const keys = try arena.dupe([]const u8, used.keys());
    sortStrings(keys);
    return .{ .used = keys, .unmatched = unmatched, .candidates = seen.count() };
}

// ── e2e 悬空引用 ─────────────────────────────────────────────────────

fn segmentCount(prefix: []const u8) usize {
    return std.mem.count(u8, prefix, ".");
}

/// 源码清单的查询索引：判断 e2e 里的一个候选字符串是否还对得上源码。
pub const SourceIndex = struct {
    exact: std.StringHashMapUnmanaged(void) = .empty,
    keys: []const []const u8,
    /// 全部运行期前缀（不带 `prefix:`）。
    prefixes: []const []const u8,
    patterns: []const []const u8,
    /// 源码里的后缀字面量（`.popover`）：`已覆盖的 id ++ 后缀` 也算覆盖。
    suffixes: []const []const u8,
    roots: std.StringHashMapUnmanaged(void) = .empty,

    pub fn init(arena: std.mem.Allocator, source_keys: []const []const u8, patterns: []const []const u8, suffixes: []const []const u8) !SourceIndex {
        var self: SourceIndex = .{ .keys = source_keys, .prefixes = &.{}, .patterns = patterns, .suffixes = suffixes };
        var prefixes: std.ArrayList([]const u8) = .empty;
        for (source_keys) |k| {
            const is_prefix = std.mem.startsWith(u8, k, "prefix:");
            const v = if (is_prefix) k["prefix:".len..] else k;
            if (is_prefix) try prefixes.append(arena, v) else try self.exact.put(arena, v, {});
            try self.roots.put(arena, v[0 .. std.mem.indexOfScalar(u8, v, '.') orelse v.len], {});
        }
        self.prefixes = prefixes.items;
        return self;
    }

    /// 一级前缀不属于源码 test_id 的字符串不归这项检查管（配置键、主机名、别的命名空间）。
    pub fn owns(self: *const SourceIndex, c: Candidate) bool {
        return self.roots.contains(c.root());
    }

    fn coversId(self: *const SourceIndex, id: []const u8) bool {
        if (self.exact.contains(id)) return true;
        for (self.prefixes) |p| if (segmentCount(p) >= 2 and std.mem.startsWith(u8, id, p)) return true;
        for (self.patterns) |g| if (globMatch(g, id)) return true;
        return false;
    }

    /// 候选是否仍被源码覆盖。
    /// - 完整 id：与静态 id 相等；或以某个**至少两段**的运行期前缀开头（`settings.field.`）；或匹配某个格式串
    ///   通配（`wizard.*.error`）；或是“按前述规则覆盖的 id ++ 源码里的某个后缀字面量”（`bmc.boot` ++ `.popover`）。
    ///   单段前缀（`ai.`、`wizard.`）覆盖整个命名空间，不能证明任何具体 id 存在，不算。
    /// - 前缀（e2e 里的模板串 / 拼接）：源码里有以它开头的 id、前缀或通配，或它落在某个至少两段的前缀之下。
    pub fn covers(self: *const SourceIndex, c: Candidate) bool {
        if (!c.prefix) {
            if (self.coversId(c.value)) return true;
            for (self.suffixes) |suffix| {
                if (c.value.len > suffix.len and std.mem.endsWith(u8, c.value, suffix) and self.coversId(c.value[0 .. c.value.len - suffix.len])) return true;
            }
            return false;
        }
        for (self.keys) |k| {
            const v = if (std.mem.startsWith(u8, k, "prefix:")) k["prefix:".len..] else k;
            if (std.mem.startsWith(u8, v, c.value)) return true;
        }
        for (self.prefixes) |p| if (segmentCount(p) >= 2 and std.mem.startsWith(u8, c.value, p)) return true;
        for (self.patterns) |g| {
            const head = g[0..std.mem.indexOfScalar(u8, g, '*').?];
            if (std.mem.startsWith(u8, head, c.value)) return true;
            if (segmentCount(head) >= 2 and std.mem.startsWith(u8, c.value, head)) return true;
        }
        return false;
    }
};

/// 一个 e2e 脚本里悬空的 test_id：形似 id、一级前缀属于源码 test_id、但源码里已经对不上的字符串
/// （排序、去重；前缀记作 `prefix:<…>.`）。
pub fn dangling(arena: std.mem.Allocator, index: *const SourceIndex, strings: []const []const u8, exclude_suffixes: []const []const u8) ![]const []const u8 {
    var out: std.StringArrayHashMapUnmanaged(void) = .empty;
    for (strings) |s| {
        const c = classify(s, exclude_suffixes) orelse continue;
        if (!index.owns(c) or index.covers(c)) continue;
        try out.put(arena, try c.key(arena), {});
    }
    const keys = try arena.dupe([]const u8, out.keys());
    sortStrings(keys);
    return keys;
}

// ── 测试 ─────────────────────────────────────────────────────────────

const testing = std.testing;
const no_suffix = [_][]const u8{ ".zig", ".json" };

test "id shape and classification" {
    try testing.expect(isIdShape("settings.nav.appearance"));
    try testing.expect(isIdShape("ai.execution.result.summary"));
    try testing.expect(isIdShape("tabs.tab-1"));
    try testing.expect(!isIdShape("settings"));
    try testing.expect(!isIdShape("Settings.nav"));
    try testing.expect(!isIdShape("a..b"));
    try testing.expect(!isIdShape("a.b."));
    try testing.expect(!isIdShape("hello world.x"));
    const exact = classify("settings.nav.appearance", &no_suffix).?;
    try testing.expect(!exact.prefix);
    const p1 = classify("settings.key.row.", &no_suffix).?;
    try testing.expect(p1.prefix);
    try testing.expectEqualStrings("settings.key.row.", p1.value);
    const p2 = classify("ai.session.{s}.{d}", &no_suffix).?;
    try testing.expectEqualStrings("ai.session.", p2.value);
    try testing.expect(p2.prefix);
    const p3 = classify("group.broadcast.member.{d}.select", &no_suffix).?;
    try testing.expectEqualStrings("group.broadcast.member.", p3.value);
    const p4 = classify("settings.field.${key}", &no_suffix).?;
    try testing.expectEqualStrings("settings.field.", p4.value);
    try testing.expect(classify("settings.json", &no_suffix) == null);
    try testing.expect(classify("main.zig", &no_suffix) == null);
    try testing.expect(classify(".timing", &no_suffix) == null);
    try testing.expect(classify("{s}.x", &no_suffix) == null);
    try testing.expect(classify("ai.row{d}", &no_suffix) != null);
}

fn collect(arena: std.mem.Allocator, sources: []const struct { [:0]const u8, bool }) ![]const []const u8 {
    var c: Collector = .{ .arena = arena, .exclude_suffixes = &no_suffix, .contexts = &.{ "test_id", "testId", "stableId" } };
    for (sources) |s| {
        const toks = try scan.tokenize(arena, s[0]);
        try c.addSource(s[0], toks, s[1]);
    }
    return c.finish();
}

test "test_id extraction: every source spelling in the repo" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const src =
        \\fn mount() !void {
        \\    root.meta.ownership.meta.test_id = "settings.nav.appearance";
        \\    options[i] = .{ .value = v, .label = "", .test_id = std.fmt.comptimePrint("ai.interaction.option.{d}", .{i}) };
        \\    row.meta.ownership.meta.test_id = try controls.stableId(bound.scope, "settings.key.row.", @tagName(a));
        \\    node.meta.ownership.meta.test_id = try std.fmt.bufPrint(&buf, "ai.session.{s}.{d}", .{ x, y });
        \\    button.meta.ownership.meta.test_id = "legacy.auth." ++ @tagName(kind);
        \\    node.meta.ownership.meta.test_id = try stableId(scope, field.key, ".timing");
        \\    const items = .{ .{ "ai.stop", "停止" }, .{ "ai.panel", "面板" } };
        \\    button.meta.ownership.meta.test_id = item[0];
        \\    const path = "config.json";
        \\    const unrelated = "com.apple.security";
        \\    const label = "zh.cn";
        \\}
        \\pub fn stableId(scope: anytype, prefix: []const u8) ![]const u8 {
        \\    const inner = "zz.decl.body";
        \\    return inner;
        \\}
        \\test "x" { _ = find(root, "settings.nav.only_in_test"); }
    ;
    const yix =
        \\pub fn Nav() View { return <row testId="settings.nav.root" />; }
    ;
    const tests_file =
        \\test "y" { _ = find(root, "ai.session.row.3"); }
        \\const k = "settings.only_test_file";
    ;
    const keys = try collect(a, &.{ .{ src, false }, .{ yix, false }, .{ tests_file, true } });
    const want = [_][]const u8{
        "ai.panel",
        "ai.stop",
        "prefix:ai.interaction.option.",
        "prefix:ai.session.",
        "prefix:legacy.auth.",
        "prefix:settings.key.row.",
        "settings.nav.appearance",
        "settings.nav.root",
    };
    if (keys.len != want.len) {
        for (keys) |k| std.debug.print("got {s}\n", .{k});
    }
    try testing.expectEqual(want.len, keys.len);
    for (want, keys) |w, k| try testing.expectEqualStrings(w, k);
}

test "e2e: string scanning and cross reference" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const ts =
        \\// h.query('commented.out')
        \\const a = await h.query('ai.stop');
        \\const b = h.query("settings.nav.appearance");
        \\const c = h.query(`settings.field.${key}`);
        \\const d = h.query(`ai.session.row.${rows[i].id}`);
        \\/* 'block.comment' */
        \\const e = 'it\'s.fine';
        \\const f = "file.json";
        \\const g = 'nothing.matches.here';
        \\const h = 'ai.other.thing';
    ;
    const strings = try scriptStrings(a, ts);
    var saw_template = false;
    for (strings) |s| if (std.mem.eql(u8, s, "settings.field.${")) {
        saw_template = true;
    };
    try testing.expect(saw_template);
    for (strings) |s| try testing.expect(!std.mem.eql(u8, s, "commented.out") and !std.mem.eql(u8, s, "block.comment"));
    const source_keys = [_][]const u8{ "ai.panel", "ai.stop", "prefix:ai.", "prefix:ai.session.", "prefix:settings.field.", "settings.nav.appearance" };
    const use = try crossReference(a, &source_keys, strings, &no_suffix);
    const want = [_][]const u8{ "ai.stop", "prefix:ai.", "prefix:ai.session.", "prefix:settings.field.", "settings.nav.appearance" };
    try testing.expectEqual(want.len, use.used.len);
    for (want, use.used) |w, k| try testing.expectEqualStrings(w, k);
    try testing.expectEqual(@as(usize, 1), use.unmatched);
}

test "format strings become globs; only the ones with a literal tail" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    try testing.expectEqualStrings("wizard.*.error", (try globOf(a, "wizard.{s}.error")).?);
    try testing.expectEqualStrings("tabs.tab.*.close", (try globOf(a, "tabs.tab.{d}.close")).?);
    try testing.expectEqualStrings("ai.session.*.row", (try globOf(a, "ai.session.{s}{d}.row")).?);
    try testing.expect((try globOf(a, "ai.session.{s}.{d}")) == null); // 以占位符结尾：前缀规则
    try testing.expect((try globOf(a, "wizard.ssh.error")) == null);
    try testing.expect((try globOf(a, "{s}.x")) == null);
    try testing.expect((try globOf(a, "hello {s}.x")) == null);
    try testing.expect(globMatch("wizard.*.error", "wizard.host.error"));
    try testing.expect(globMatch("wizard.*.error", "wizard.key.path.error"));
    try testing.expect(!globMatch("wizard.*.error", "wizard..error"));
    try testing.expect(!globMatch("wizard.*.error", "wizard.host.errors"));
    try testing.expect(!globMatch("wizard.*.error", "wizard.error"));
    try testing.expect(isSuffixShape(".popover", &no_suffix));
    try testing.expect(isSuffixShape(".close.tooltip", &no_suffix));
    try testing.expect(!isSuffixShape(".json", &no_suffix));
    try testing.expect(!isSuffixShape(".", &no_suffix));
    try testing.expect(!isSuffixShape("..x", &no_suffix));
    try testing.expect(!isSuffixShape(".Popover", &no_suffix));
    try testing.expect(!isSuffixShape("popover", &no_suffix));
}

test "e2e dangling: ids that no longer exist in the sources" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const src =
        \\fn mount() !void {
        \\    a.meta.ownership.meta.test_id = "sidebar.footer.new";
        \\    b.meta.ownership.meta.test_id = "sidebar.search";
        \\    c.meta.ownership.meta.test_id = try stableId(scope, "settings.field.", key);
        \\    d.meta.ownership.meta.test_id = try std.fmt.allocPrint(alloc, "wizard.{s}.error", .{@tagName(kind)});
        \\    e.meta.ownership.meta.test_id = "notifications.toast.0";
        \\    if (std.mem.startsWith(u8, key, "ai.")) return;
        \\    f.meta.ownership.meta.test_id = "ai.stop";
        \\    g.meta.ownership.meta.test_id = "bmc.boot";
        \\    popup.meta.ownership.meta.test_id = try scopedId(scope, id, ".popover");
        \\    const path = "key.pem";
        \\}
    ;
    var c: Collector = .{ .arena = a, .exclude_suffixes = &no_suffix, .contexts = &.{ "test_id", "stableId" } };
    try c.addSource(src, try scan.tokenize(a, src), false);
    const keys = try c.finish();
    const index = try SourceIndex.init(a, keys, try c.finishPatterns(), c.suffixes.keys());
    const ts =
        \\await h.clickTestId('sidebar.new');             // 已删除
        \\await h.clickTestId('sidebar.footer.new');
        \\await h.query(`settings.field.${key}`);
        \\await h.query('settings.field.terminal.font_size');
        \\await h.query('settings.close');                // 已删除
        \\await h.query('wizard.host.error');             // 格式串
        \\await h.query('wizard.panel');                  // 单段前缀 wizard. 不作数
        \\await h.query('ai.approval.accept');            // `ai.` 只是 startsWith 检查
        \\await h.query('ai.stop');
        \\await h.query('notifications.toast.' + i);
        \\await h.query('notifications.dismiss.' + i);    // 源码里没有任何 notifications.dismiss.*
        \\await h.query(`sidebar.rail.host.${i}`);        // 同上
        \\await h.query('bmc.boot.popover');              // bmc.boot ++ ".popover"
        \\await h.query('bmc.power.popover');             // 没有 bmc.power
        \\const host = 'example.com'; const key = 'terminal.font_size'; const f = 'report.json';
    ;
    const got = try dangling(a, &index, try scriptStrings(a, ts), &no_suffix);
    const want = [_][]const u8{ "ai.approval.accept", "bmc.power.popover", "prefix:notifications.dismiss.", "prefix:sidebar.rail.host.", "settings.close", "sidebar.new", "wizard.panel" };
    if (got.len != want.len) for (got) |k| std.debug.print("got {s}\n", .{k});
    try testing.expectEqual(want.len, got.len);
    for (want, got) |w, k| try testing.expectEqualStrings(w, k);
}
