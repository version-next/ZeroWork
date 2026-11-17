//! check-arch：ZeroWork UI 架构护栏（docs/ui-revamp/ARCHITECTURE_PLAN.md §4.3、§6.3）。
//!
//!   check_arch [all]                 import 分层检查（含术语表禁用词）+ test_id 检查（`zig build check-arch` 跑这个）
//!   check_arch imports [--prune | --update-baseline]
//!   check_arch test-ids [--prune | --update-baseline]
//!   check_arch count-tests ROOT.zig...
//!   check_arch list-imports FILE...  逐条打印分词器提取的 @import（调试、V-9 核对用）
//!
//! 公共选项（路径相对当前目录，build 步骤把 cwd 设为仓库根）：
//!   --rules PATH          默认 tools/arch/rules.zon
//!   --baseline PATH       默认 tools/arch/baseline.txt
//!   --ids-baseline PATH   默认 tools/arch/test_ids.baseline.txt
//!   --e2e-used PATH       默认 tools/arch/test_ids.e2e_used.txt
//!   --e2e-dangling PATH   默认 tools/arch/test_ids.e2e_dangling.txt（e2e 悬空 test_id 的欠账基线）
//!   --e2e-ignore PATH     默认 tools/arch/test_ids.e2e_ignore.txt（e2e 有意引用的、源码里不存在的 id）
//!   --verbose             额外打印明细
//!
//! 退出码：0 通过；1 有新增违规 / 基线 id 丢失 / e2e 新出现悬空 test_id；2 用法或规则文件错误。
//! 基线只能缩短：`--update-baseline` 只用于首次生成或经书面认可的整体重建，
//! 日常不得用它吞掉新增违规；源码修好后用 `--prune` 删除已消失的条目。
const std = @import("std");
const rules_mod = @import("rules.zig");
const scan = @import("scan.zig");
const test_ids = @import("test_ids.zig");
const Rules = rules_mod.Rules;

const Options = struct {
    command: []const u8 = "all",
    rules_path: []const u8 = "tools/arch/rules.zon",
    baseline_path: []const u8 = "tools/arch/baseline.txt",
    ids_baseline_path: []const u8 = "tools/arch/test_ids.baseline.txt",
    e2e_used_path: []const u8 = "tools/arch/test_ids.e2e_used.txt",
    e2e_dangling_path: []const u8 = "tools/arch/test_ids.e2e_dangling.txt",
    e2e_ignore_path: []const u8 = "tools/arch/test_ids.e2e_ignore.txt",
    prune: bool = false,
    update: bool = false,
    verbose: bool = false,
    positional: []const []const u8 = &.{},
};

const Ctx = struct {
    arena: std.mem.Allocator,
    gpa: std.mem.Allocator,
    io: std.Io,
    out: *std.Io.Writer,
    opts: Options,
};

pub fn main(init: std.process.Init) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var aw: std.Io.Writer.Allocating = .init(arena);
    const code = run(.{ .arena = arena, .gpa = init.gpa, .io = init.io, .out = &aw.writer, .opts = .{} }, args[1..]) catch |err| blk: {
        aw.writer.print("check-arch: 错误 {s}\n", .{@errorName(err)}) catch {};
        break :blk 2;
    };
    const file = if (code == 0) std.Io.File.stdout() else std.Io.File.stderr();
    try file.writeStreamingAll(init.io, aw.written());
    if (code != 0) std.process.exit(code);
}

fn run(ctx_in: Ctx, args: []const [:0]const u8) !u8 {
    var ctx = ctx_in;
    var positional: std.ArrayList([]const u8) = .empty;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--prune")) {
            ctx.opts.prune = true;
        } else if (std.mem.eql(u8, a, "--update-baseline")) {
            ctx.opts.update = true;
        } else if (std.mem.eql(u8, a, "--verbose")) {
            ctx.opts.verbose = true;
        } else if (std.mem.startsWith(u8, a, "--")) {
            if (i + 1 >= args.len) return usage(ctx);
            const v = args[i + 1];
            i += 1;
            if (std.mem.eql(u8, a, "--rules")) ctx.opts.rules_path = v else if (std.mem.eql(u8, a, "--baseline")) ctx.opts.baseline_path = v else if (std.mem.eql(u8, a, "--ids-baseline")) ctx.opts.ids_baseline_path = v else if (std.mem.eql(u8, a, "--e2e-used")) ctx.opts.e2e_used_path = v else if (std.mem.eql(u8, a, "--e2e-dangling")) ctx.opts.e2e_dangling_path = v else if (std.mem.eql(u8, a, "--e2e-ignore")) ctx.opts.e2e_ignore_path = v else return usage(ctx);
        } else try positional.append(ctx.arena, a);
    }
    if (positional.items.len > 0) {
        ctx.opts.command = positional.items[0];
        ctx.opts.positional = positional.items[1..];
    }
    if (ctx.opts.prune and ctx.opts.update) return usage(ctx);

    const cmd = ctx.opts.command;
    if (std.mem.eql(u8, cmd, "count-tests")) return countTestsCommand(ctx);
    if (std.mem.eql(u8, cmd, "list-imports")) return listImportsCommand(ctx);

    const rules_source = try readZ(ctx, ctx.opts.rules_path);
    const rules = rules_mod.parse(ctx.gpa, ctx.arena, rules_source, ctx.opts.rules_path) catch return 2;
    const undefined_layers = try rules_mod.undefinedLayers(ctx.arena, &rules);
    if (undefined_layers.len != 0) {
        for (undefined_layers) |l| try ctx.out.print("rules.zon: 层 `{s}` 没有 allow 条目\n", .{l});
        return 2;
    }

    if (std.mem.eql(u8, cmd, "imports")) return importsCommand(ctx, &rules);
    if (std.mem.eql(u8, cmd, "test-ids")) return testIdsCommand(ctx, &rules);
    if (std.mem.eql(u8, cmd, "all")) {
        if (ctx.opts.prune or ctx.opts.update) return usage(ctx);
        const a = try importsCommand(ctx, &rules);
        try ctx.out.writeAll("\n");
        const b = try testIdsCommand(ctx, &rules);
        return @max(a, b);
    }
    return usage(ctx);
}

fn usage(ctx: Ctx) u8 {
    ctx.out.writeAll(
        \\usage: check_arch [all]
        \\       check_arch imports [--prune | --update-baseline]
        \\       check_arch test-ids [--prune | --update-baseline]
        \\       check_arch count-tests ROOT.zig...
        \\       check_arch list-imports FILE...
        \\options: --rules PATH --baseline PATH --ids-baseline PATH --e2e-used PATH --e2e-dangling PATH --e2e-ignore PATH --verbose
        \\
    ) catch {};
    return 2;
}

fn readZ(ctx: Ctx, path: []const u8) ![:0]const u8 {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(ctx.io, path, ctx.arena, .limited(64 * 1024 * 1024));
    return ctx.arena.dupeSentinel(u8, bytes, 0);
}

fn readOptional(ctx: Ctx, path: []const u8) !?[]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(ctx.io, path, ctx.arena, .limited(64 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => null,
        else => err,
    };
}

fn writeLines(ctx: Ctx, path: []const u8, header: []const u8, lines: []const []const u8) !void {
    var buf: std.ArrayList(u8) = .empty;
    try buf.appendSlice(ctx.arena, header);
    for (lines) |l| {
        try buf.appendSlice(ctx.arena, l);
        try buf.append(ctx.arena, '\n');
    }
    try std.Io.Dir.cwd().writeFile(ctx.io, .{ .sub_path = path, .data = buf.items });
}

/// 读基线：忽略空行与 `#` 注释行。
pub fn parseLines(arena: std.mem.Allocator, bytes: []const u8) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var it = std.mem.splitScalar(u8, bytes, '\n');
    while (it.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        try out.append(arena, line);
    }
    return out.items;
}

fn walkFiles(ctx: Ctx, roots: []const []const u8, extensions: []const []const u8, skip: []const []const u8) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (roots) |root| {
        var dir = std.Io.Dir.cwd().openDir(ctx.io, root, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
        defer dir.close(ctx.io);
        var walker = try dir.walk(ctx.arena);
        defer walker.deinit();
        while (try walker.next(ctx.io)) |entry| {
            if (entry.kind != .file) continue;
            var ext_ok = false;
            for (extensions) |ext| if (std.mem.endsWith(u8, entry.basename, ext)) {
                ext_ok = true;
            };
            if (!ext_ok) continue;
            const path = try std.fmt.allocPrint(ctx.arena, "{s}/{s}", .{ root, entry.path });
            if (rules_mod.matchAny(skip, path)) continue;
            try out.append(ctx.arena, path);
        }
    }
    test_ids.sortStrings(out.items);
    return out.items;
}

// ── imports ──────────────────────────────────────────────────────────

pub const Violation = struct {
    rule: []const u8,
    src: []const u8,
    target: []const u8,
    line: u32,
    src_layer: []const u8,

    pub fn key(v: Violation, arena: std.mem.Allocator) ![]const u8 {
        return std.fmt.allocPrint(arena, "{s} {s} → {s}", .{ v.rule, v.src, v.target });
    }
};

pub const FileReport = struct {
    imports: usize = 0,
    transitional: bool = false,
};

/// 检查一份源文件，把违规追加到 `out`。
pub fn checkFile(arena: std.mem.Allocator, rules: *const Rules, path: []const u8, source: [:0]const u8, out: *std.ArrayList(Violation)) !FileReport {
    var report: FileReport = .{};
    const src = rules_mod.classifyPath(rules, path) orelse {
        try out.append(arena, .{ .rule = "unclassified-source", .src = path, .target = "-", .line = 0, .src_layer = "?" });
        return report;
    };
    report.transitional = src.transitional;
    const is_test_file = rules_mod.matchAny(rules.test_files, path);
    const toks = try scan.tokenize(arena, source);
    const list = try scan.imports(arena, source, toks);
    report.imports = list.len;
    for (list) |imp| {
        const in_test = is_test_file or imp.in_test;
        var target: []const u8 = imp.spec;
        const dst = if (scan.isFileImport(imp.spec)) blk: {
            target = try scan.normalize(arena, scan.dirname(path), imp.spec);
            break :blk rules_mod.classifyPath(rules, target) orelse {
                try out.append(arena, .{ .rule = "unclassified-target", .src = path, .target = target, .line = imp.line, .src_layer = src.layer });
                continue;
            };
        } else rules_mod.classifyModule(rules, imp.spec) orelse {
            try out.append(arena, .{ .rule = "unclassified-module", .src = path, .target = target, .line = imp.line, .src_layer = src.layer });
            continue;
        };
        switch (rules_mod.judge(rules, src, dst, in_test)) {
            .ok => {},
            .layer => try out.append(arena, .{ .rule = try std.fmt.allocPrint(arena, "layer:{s}->{s}", .{ src.layer, dst.layer }), .src = path, .target = target, .line = imp.line, .src_layer = src.layer }),
            .cross_feature => try out.append(arena, .{ .rule = "cross-feature", .src = path, .target = target, .line = imp.line, .src_layer = src.layer }),
        }
    }
    if (!is_test_file and rules_mod.matchAny(rules.terms.files, path) and !rules_mod.matchAny(rules.terms.skip, path)) {
        try checkTerms(arena, &rules.terms, "term", path, source, toks, src.layer, out);
    }
    if (!is_test_file and rules_mod.matchAny(rules.shortcut_text.files, path) and !rules_mod.matchAny(rules.shortcut_text.skip, path)) {
        try checkTerms(arena, &rules.shortcut_text, "shortcut-text", path, source, toks, src.layer, out);
    }
    if (!is_test_file) {
        var hits: std.ArrayList(scan.SequenceHit) = .empty;
        for (rules.idents) |rule| {
            if (!rules_mod.matchAny(rule.files, path) or rules_mod.matchAny(rule.skip, path)) continue;
            for (rule.forbid) |seq| {
                hits.clearRetainingCapacity();
                try scan.findSequenceHits(source, toks, seq, rule.reads_only, &hits, arena);
                for (hits.items) |hit| {
                    const target = if (rule.per_function) try std.fmt.allocPrint(arena, "{s} @ {s}", .{ seq, scan.enclosingFunction(source, toks, hit.token) }) else seq;
                    try out.append(arena, .{ .rule = try std.fmt.allocPrint(arena, "ident:{s}", .{rule.name}), .src = path, .target = target, .line = hit.line, .src_layer = src.layer });
                }
            }
        }
    }
    return report;
}

/// 术语表护栏：用户可见字符串里的禁用词 → `term:<禁用词>` 违规（目标为应改用的说法）。
/// `.zig` 只看非测试代码里的字符串字面量（注释、标识符、test 块不算）；`.yix` 的模板文字不是
/// Zig 字面量，按行扫描，跳过 `//` 注释行。白名单见 rules.zon `terms.allow`。
/// 快捷键文字护栏（`shortcut_text`）用同一套扫描，规则名前缀为 `shortcut-text:`。
fn checkTerms(arena: std.mem.Allocator, terms: *const rules_mod.Terms, prefix: []const u8, path: []const u8, source: [:0]const u8, toks: []const scan.Tok, layer: []const u8, out: *std.ArrayList(Violation)) !void {
    const yix = std.mem.endsWith(u8, path, ".yix");
    for (terms.forbid) |rule| {
        if (terms.allowed(path, rule.term)) continue;
        const name = try std.fmt.allocPrint(arena, "{s}:{s}", .{ prefix, rule.term });
        if (yix) {
            var line_no: u32 = 1;
            var it = std.mem.splitScalar(u8, source, '\n');
            while (it.next()) |line| : (line_no += 1) {
                const trimmed = std.mem.trimStart(u8, line, " \t");
                if (std.mem.startsWith(u8, trimmed, "//")) continue;
                if (std.mem.indexOf(u8, line, rule.term) != null) try out.append(arena, .{ .rule = name, .src = path, .target = rule.use, .line = line_no, .src_layer = layer });
            }
            continue;
        }
        for (toks) |t| {
            if (t.in_test) continue;
            if (t.tag != .string_literal and t.tag != .multiline_string_literal_line) continue;
            if (std.mem.indexOf(u8, scan.text(source, t), rule.term) != null) try out.append(arena, .{ .rule = name, .src = path, .target = rule.use, .line = t.line, .src_layer = layer });
        }
    }
}

pub const Diff = struct {
    /// 不在基线里的当前违规 key
    new: []const []const u8,
    /// 在基线里但已消失的 key
    stale: []const []const u8,
    /// 当前全部 key（排序、去重）
    current: []const []const u8,
};

pub fn diffBaseline(arena: std.mem.Allocator, current_keys: []const []const u8, baseline: []const []const u8) !Diff {
    var cur: std.StringArrayHashMapUnmanaged(void) = .empty;
    for (current_keys) |k| try cur.put(arena, k, {});
    var base: std.StringHashMapUnmanaged(void) = .empty;
    for (baseline) |k| try base.put(arena, k, {});
    var new: std.ArrayList([]const u8) = .empty;
    for (cur.keys()) |k| if (!base.contains(k)) try new.append(arena, k);
    var stale: std.ArrayList([]const u8) = .empty;
    var stale_seen: std.StringHashMapUnmanaged(void) = .empty;
    for (baseline) |k| if (!cur.contains(k) and !(try stale_seen.getOrPut(arena, k)).found_existing) try stale.append(arena, k);
    const current = try arena.dupe([]const u8, cur.keys());
    test_ids.sortStrings(current);
    test_ids.sortStrings(new.items);
    test_ids.sortStrings(stale.items);
    return .{ .new = new.items, .stale = stale.items, .current = current };
}

/// `--prune`：从基线中删掉已消失的条目，保留其余条目原样（不会加入新条目）。
pub fn pruneBaseline(arena: std.mem.Allocator, baseline: []const []const u8, stale: []const []const u8) ![]const []const u8 {
    var drop: std.StringHashMapUnmanaged(void) = .empty;
    for (stale) |k| try drop.put(arena, k, {});
    var keep: std.StringArrayHashMapUnmanaged(void) = .empty;
    for (baseline) |k| if (!drop.contains(k)) try keep.put(arena, k, {});
    const out = try arena.dupe([]const u8, keep.keys());
    test_ids.sortStrings(out);
    return out;
}

const baseline_header =
    \\# check-arch 已知违规基线（tools/arch/README.md）。
    \\# 格式：规则 来源文件 → 目标；不含行号；排序、去重。
    \\# 只能缩短：修掉违规后运行 `check_arch imports --prune`；不得手工或用 --update-baseline 吞新增违规。
    \\
;

fn importsCommand(ctx: Ctx, rules: *const Rules) !u8 {
    const files = try walkFiles(ctx, rules.roots, rules.extensions, rules.skip);
    var violations: std.ArrayList(Violation) = .empty;
    var import_count: usize = 0;
    var transitional_files: usize = 0;
    for (files) |path| {
        const source = try readZ(ctx, path);
        const rep = try checkFile(ctx.arena, rules, path, source, &violations);
        import_count += rep.imports;
        if (rep.transitional) transitional_files += 1;
    }

    var keys: std.ArrayList([]const u8) = .empty;
    var first_of: std.StringArrayHashMapUnmanaged(Violation) = .empty;
    for (violations.items) |v| {
        const k = try v.key(ctx.arena);
        try keys.append(ctx.arena, k);
        const gop = try first_of.getOrPut(ctx.arena, k);
        if (!gop.found_existing) gop.value_ptr.* = v;
    }
    const baseline_bytes = try readOptional(ctx, ctx.opts.baseline_path);
    const baseline = if (baseline_bytes) |b| try parseLines(ctx.arena, b) else &[_][]const u8{};
    const diff = try diffBaseline(ctx.arena, keys.items, baseline);

    const out = ctx.out;
    try out.print("check-arch imports: 扫描 {d} 个文件（其中 {d} 个落在过渡条目上），{d} 处 @import\n", .{ files.len, transitional_files, import_count });

    if (ctx.opts.update) {
        try writeLines(ctx, ctx.opts.baseline_path, baseline_header, diff.current);
        try out.print("已重写基线 {s}：{d} 条（只用于首次生成或经认可的重建）\n", .{ ctx.opts.baseline_path, diff.current.len });
    } else if (ctx.opts.prune) {
        const kept = try pruneBaseline(ctx.arena, baseline, diff.stale);
        try writeLines(ctx, ctx.opts.baseline_path, baseline_header, kept);
        try out.print("--prune：从基线删除 {d} 条已消失的条目，剩余 {d} 条\n", .{ diff.stale.len, kept.len });
    }

    try printStats(ctx, diff.current, &first_of);

    if (!ctx.opts.prune and !ctx.opts.update and diff.stale.len > 0) {
        try out.print("\n基线中有 {d} 条已不存在（不算失败；运行 `check_arch imports --prune` 删除）：\n", .{diff.stale.len});
        for (diff.stale) |k| try out.print("  - {s}\n", .{k});
    }

    if (!ctx.opts.update and diff.new.len > 0) {
        try out.print("\n新增违规 {d} 条（不在 {s} 中）：\n", .{ diff.new.len, ctx.opts.baseline_path });
        var new_set: std.StringHashMapUnmanaged(void) = .empty;
        for (diff.new) |k| try new_set.put(ctx.arena, k, {});
        for (diff.new) |k| {
            try out.print("  + {s}\n", .{k});
            for (violations.items) |v| {
                if (!std.mem.eql(u8, try v.key(ctx.arena), k)) continue;
                try out.print("      {s}:{d}\n", .{ v.src, v.line });
            }
        }
        try out.writeAll("修复办法：改正 import（见 docs/ui-revamp/ARCHITECTURE_PLAN.md §4.2）；基线只能缩短，不要把新增违规加进基线。\n");
        return 1;
    }
    try out.print("check-arch imports: 通过（基线 {d} 条，当前 {d} 条，无新增）\n", .{ baseline.len, diff.current.len });
    return 0;
}

fn printStats(ctx: Ctx, current: []const []const u8, first_of: *std.StringArrayHashMapUnmanaged(Violation)) !void {
    var by_rule: std.StringArrayHashMapUnmanaged(usize) = .empty;
    var by_layer: std.StringArrayHashMapUnmanaged(usize) = .empty;
    var by_family: std.StringArrayHashMapUnmanaged(usize) = .empty;
    for (current) |k| {
        const v = first_of.get(k).?;
        (try by_rule.getOrPutValue(ctx.arena, v.rule, 0)).value_ptr.* += 1;
        (try by_layer.getOrPutValue(ctx.arena, v.src_layer, 0)).value_ptr.* += 1;
        const fam_end = std.mem.indexOfScalar(u8, v.rule, ':') orelse v.rule.len;
        (try by_family.getOrPutValue(ctx.arena, v.rule[0..fam_end], 0)).value_ptr.* += 1;
    }
    const out = ctx.out;
    try out.print("\n违规统计（按基线条目计，共 {d} 条）\n", .{current.len});
    try out.writeAll("  按规则类别：\n");
    try printCounts(ctx, &by_family);
    try out.writeAll("  按规则：\n");
    try printCounts(ctx, &by_rule);
    try out.writeAll("  按来源层：\n");
    try printCounts(ctx, &by_layer);
}

fn printCounts(ctx: Ctx, map: *std.StringArrayHashMapUnmanaged(usize)) !void {
    const Entry = struct { k: []const u8, v: usize };
    var list: std.ArrayList(Entry) = .empty;
    for (map.keys(), map.values()) |k, v| try list.append(ctx.arena, .{ .k = k, .v = v });
    std.mem.sort(Entry, list.items, {}, struct {
        fn lt(_: void, a: Entry, b: Entry) bool {
            if (a.v != b.v) return a.v > b.v;
            return std.mem.lessThan(u8, a.k, b.k);
        }
    }.lt);
    for (list.items) |e| try ctx.out.print("    {d:>5}  {s}\n", .{ e.v, e.k });
}

// ── test-ids ─────────────────────────────────────────────────────────

const ids_header =
    \\# 源码定义的 test_id 基线（tools/arch/README.md「test_id 基线」）。
    \\# 每行一个；`prefix:` 开头的是运行期拼接的前缀。确需删除或改名时，在同一提交里改本文件并写明理由。
    \\
;
const e2e_header =
    \\# 被 e2e 脚本使用的 test_id（源码清单与 e2e 字符串的交集），不可改名、不可删除。
    \\# 由 `check_arch test-ids --update-baseline` 生成。
    \\
;
const dangling_header =
    \\# e2e 悬空 test_id 欠账基线（tools/arch/README.md「e2e 悬空引用」）。
    \\# 格式：脚本 → id；排序、去重。这些脚本引用的 id 在源码里已经不存在，脚本要改成断言当前的真实契约。
    \\# 只能缩短：脚本修好后运行 `check_arch test-ids --prune`；回归清单里 runnable 的脚本优先清零。
    \\
;

fn testIdsCommand(ctx: Ctx, rules: *const Rules) !u8 {
    const files = try walkFiles(ctx, rules.roots, rules.extensions, rules.skip);
    var collector: test_ids.Collector = .{ .arena = ctx.arena, .exclude_suffixes = rules.test_ids.exclude_suffixes, .contexts = rules.test_ids.contexts };
    for (files) |path| {
        const source = try readZ(ctx, path);
        const toks = try scan.tokenize(ctx.arena, source);
        try collector.addSource(source, toks, rules_mod.matchAny(rules.test_files, path));
    }
    const current = try collector.finish();

    const e2e_files = try walkFiles(ctx, rules.test_ids.e2e_dirs, rules.test_ids.e2e_extensions, &.{});
    var e2e_strings: std.ArrayList([]const u8) = .empty;
    for (e2e_files) |path| {
        const bytes = try readZ(ctx, path);
        try e2e_strings.appendSlice(ctx.arena, try test_ids.scriptStrings(ctx.arena, bytes));
    }
    const use = try test_ids.crossReference(ctx.arena, current, e2e_strings.items, rules.test_ids.exclude_suffixes);

    // e2e 悬空引用：脚本里形似 test_id、一级前缀属于源码 test_id、但源码已经对不上的字符串。
    const index = try test_ids.SourceIndex.init(ctx.arena, current, try collector.finishPatterns(), collector.suffixes.keys());
    const ignore_bytes = try readOptional(ctx, ctx.opts.e2e_ignore_path) orelse "";
    const ignored = try parseLines(ctx.arena, ignore_bytes);
    var ignore_used: std.StringHashMapUnmanaged(void) = .empty;
    var dangling_keys: std.ArrayList([]const u8) = .empty;
    for (e2e_files) |path| {
        const bytes = try readZ(ctx, path);
        const found = try test_ids.dangling(ctx.arena, &index, try test_ids.scriptStrings(ctx.arena, bytes), rules.test_ids.exclude_suffixes);
        next: for (found) |id| {
            for (ignored) |a| if (std.mem.eql(u8, a, id)) {
                try ignore_used.put(ctx.arena, a, {});
                continue :next;
            };
            try dangling_keys.append(ctx.arena, try std.fmt.allocPrint(ctx.arena, "{s} → {s}", .{ path, id }));
        }
    }

    var n_prefix: usize = 0;
    for (current) |k| {
        if (std.mem.startsWith(u8, k, "prefix:")) n_prefix += 1;
    }
    var used_prefix: usize = 0;
    for (use.used) |k| {
        if (std.mem.startsWith(u8, k, "prefix:")) used_prefix += 1;
    }
    const out = ctx.out;
    try out.print("check-arch test-ids: 源码 {d} 个文件 → {d} 条（静态 id {d}，前缀 {d}；其中确定定义点 {d}）；测试代码里另有 {d} 个形似 id 的字面量未计入\n", .{ files.len, current.len, current.len - n_prefix, n_prefix, collector.definite.count(), collector.test_only.count() });
    try out.print("  e2e：{d} 个脚本、{d} 个形似 id 的字符串；与源码清单的交集 {d} 条（静态 id {d}，前缀 {d}）；未命中 {d}（含误报与运行期 id）\n", .{ e2e_files.len, use.candidates, use.used.len, use.used.len - used_prefix, used_prefix, use.unmatched });

    if (ctx.opts.update) {
        try writeLines(ctx, ctx.opts.ids_baseline_path, ids_header, current);
        try writeLines(ctx, ctx.opts.e2e_used_path, e2e_header, use.used);
        try out.print("已写入 {s}（{d} 条）与 {s}（{d} 条）\n", .{ ctx.opts.ids_baseline_path, current.len, ctx.opts.e2e_used_path, use.used.len });
        const dd = try diffBaseline(ctx.arena, dangling_keys.items, &.{});
        try writeLines(ctx, ctx.opts.e2e_dangling_path, dangling_header, dd.current);
        try out.print("已重写 e2e 悬空欠账基线 {s}：{d} 条（只用于首次生成或经认可的重建）\n", .{ ctx.opts.e2e_dangling_path, dd.current.len });
        return 0;
    }

    const base_bytes = try readOptional(ctx, ctx.opts.ids_baseline_path) orelse {
        try out.print("缺少 {s}；首次生成请运行 `check_arch test-ids --update-baseline`\n", .{ctx.opts.ids_baseline_path});
        return 1;
    };
    const baseline = try parseLines(ctx.arena, base_bytes);
    const e2e_bytes = try readOptional(ctx, ctx.opts.e2e_used_path) orelse "";
    const e2e_baseline = try parseLines(ctx.arena, e2e_bytes);

    const d = try diffBaseline(ctx.arena, current, baseline);
    const de = try diffBaseline(ctx.arena, use.used, e2e_baseline);
    var e2e_set: std.StringHashMapUnmanaged(void) = .empty;
    for (e2e_baseline) |k| try e2e_set.put(ctx.arena, k, {});

    try out.print("  基线 {d} 条；源码新增 {d} 条（不算失败）\n", .{ baseline.len, d.new.len });
    if (ctx.opts.verbose) for (d.new) |k| try out.print("    + {s}\n", .{k});
    if (de.new.len > 0) {
        try out.print("  e2e 新引用了 {d} 条源码 id（不算失败；重新生成基线时会并入 {s}）\n", .{ de.new.len, ctx.opts.e2e_used_path });
        if (ctx.opts.verbose) for (de.new) |k| try out.print("    + {s}\n", .{k});
    }
    if (d.stale.len > 0) {
        try out.print("\n基线中的 {d} 个 test_id 在源码中找不到：\n", .{d.stale.len});
        for (d.stale) |k| try out.print("  - {s}{s}\n", .{ k, if (e2e_set.contains(k)) "    ← 被 e2e 使用，不可改" else "" });
        try out.writeAll("test_id 是公开接口（§6.3）：恢复它；确需删除或改名时，在同一提交里改 test_ids.baseline.txt 并写明理由。\n");
        return 1;
    }
    try out.writeAll("check-arch test-ids: 通过（基线中的 id 全部仍在源码中）\n");

    const debt_bytes = try readOptional(ctx, ctx.opts.e2e_dangling_path) orelse "";
    const debt = try parseLines(ctx.arena, debt_bytes);
    const dd = try diffBaseline(ctx.arena, dangling_keys.items, debt);
    try out.print("check-arch e2e 悬空引用：当前 {d} 处（欠账基线 {d} 条，忽略清单 {d} 条）\n", .{ dd.current.len, debt.len, ignored.len });
    if (ctx.opts.prune) {
        const kept = try pruneBaseline(ctx.arena, debt, dd.stale);
        try writeLines(ctx, ctx.opts.e2e_dangling_path, dangling_header, kept);
        try out.print("--prune：从 {s} 删除 {d} 条已修好的条目，剩余 {d} 条\n", .{ ctx.opts.e2e_dangling_path, dd.stale.len, kept.len });
    } else if (dd.stale.len > 0) {
        try out.print("  欠账基线中有 {d} 条已修好（不算失败；运行 `check_arch test-ids --prune` 删除）\n", .{dd.stale.len});
        if (ctx.opts.verbose) for (dd.stale) |k| try out.print("    - {s}\n", .{k});
    }
    var ignore_stale: usize = 0;
    for (ignored) |a| {
        if (ignore_used.contains(a)) continue;
        ignore_stale += 1;
        try out.print("  {s}: `{s}` 已不再悬空（源码里有了，或没有脚本再引用），请从该文件删除\n", .{ ctx.opts.e2e_ignore_path, a });
    }
    if (dd.new.len > 0) {
        try out.print("\ne2e 脚本引用了 {d} 处源码里不存在的 test_id（不在 {s} 中）：\n", .{ dd.new.len, ctx.opts.e2e_dangling_path });
        for (dd.new) |k| try out.print("  + {s}\n", .{k});
        try out.print("修复办法：把脚本改成断言当前的真实 test_id（源码为准；删除 / 改名的 id 见 git log -S）。脚本有意断言某个 id 已不存在时，\n把该 id 连同理由写进 {s}。欠账基线只能缩短，不要把新增悬空引用加进去。\n", .{ctx.opts.e2e_ignore_path});
        return 1;
    }
    if (ignore_stale > 0) return 1;
    try out.writeAll("check-arch e2e 悬空引用: 通过（无新增）\n");
    return 0;
}

// ── count-tests ──────────────────────────────────────────────────────

fn listImportsCommand(ctx: Ctx) !u8 {
    if (ctx.opts.positional.len == 0) return usage(ctx);
    var total: usize = 0;
    for (ctx.opts.positional) |path| {
        const source = try readZ(ctx, path);
        const toks = try scan.tokenize(ctx.arena, source);
        const list = try scan.imports(ctx.arena, source, toks);
        for (list) |imp| try ctx.out.print("{s}:{d}: {s}{s}\n", .{ path, imp.line, imp.spec, if (imp.in_test) "  (test)" else "" });
        total += list.len;
    }
    try ctx.out.print("list-imports: {d} 个文件，{d} 处 @import\n", .{ ctx.opts.positional.len, total });
    return 0;
}

fn countTestsCommand(ctx: Ctx) !u8 {
    if (ctx.opts.positional.len == 0) return usage(ctx);
    const out = ctx.out;
    try out.writeAll("count-tests：沿相对 @import 闭包统计 `test` 块（静态上界，见 README）\n");
    try out.writeAll("  根文件                                   文件数   具名   decltest  匿名   合计\n");
    for (ctx.opts.positional) |root| {
        var seen: std.StringArrayHashMapUnmanaged(void) = .empty;
        var queue: std.ArrayList([]const u8) = .empty;
        try queue.append(ctx.arena, root);
        try seen.put(ctx.arena, root, {});
        var total: scan.TestCount = .{};
        var qi: usize = 0;
        while (qi < queue.items.len) : (qi += 1) {
            const path = queue.items[qi];
            const source = readZ(ctx, path) catch |err| switch (err) {
                error.FileNotFound => continue,
                else => return err,
            };
            const toks = try scan.tokenize(ctx.arena, source);
            const c = scan.countTests(toks);
            total.named += c.named;
            total.decl += c.decl;
            total.unnamed += c.unnamed;
            for (try scan.imports(ctx.arena, source, toks)) |imp| {
                if (!std.mem.endsWith(u8, imp.spec, ".zig")) continue;
                const target = try scan.normalize(ctx.arena, scan.dirname(path), imp.spec);
                if ((try seen.getOrPut(ctx.arena, target)).found_existing) continue;
                try queue.append(ctx.arena, target);
            }
        }
        try out.print("  {s:<40} {d:>6} {d:>6} {d:>9} {d:>5} {d:>6}\n", .{ root, seen.count(), total.named, total.decl, total.unnamed, total.total() });
    }
    return 0;
}

// ── 测试 ─────────────────────────────────────────────────────────────

const testing = std.testing;

test {
    _ = rules_mod;
    _ = scan;
    _ = test_ids;
}

test "baseline diff, prune and stable ordering" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const current = [_][]const u8{ "r b → x", "r a → x", "r a → x", "r c → y" };
    const baseline = try parseLines(a,
        \\# comment
        \\r a → x
        \\
        \\r gone → z
        \\r b → x
        \\r gone → z
    );
    const d = try diffBaseline(a, &current, baseline);
    try testing.expectEqual(@as(usize, 3), d.current.len);
    try testing.expectEqualStrings("r a → x", d.current[0]);
    try testing.expectEqualStrings("r c → y", d.current[2]);
    try testing.expectEqual(@as(usize, 1), d.new.len);
    try testing.expectEqualStrings("r c → y", d.new[0]);
    try testing.expectEqual(@as(usize, 1), d.stale.len);
    try testing.expectEqualStrings("r gone → z", d.stale[0]);
    const pruned = try pruneBaseline(a, baseline, d.stale);
    try testing.expectEqual(@as(usize, 2), pruned.len);
    try testing.expectEqualStrings("r a → x", pruned[0]);
    try testing.expectEqualStrings("r b → x", pruned[1]);
    // prune 绝不加入新条目
    for (pruned) |k| try testing.expect(!std.mem.eql(u8, k, "r c → y"));
}

fn checkSource(a: std.mem.Allocator, rules: *const Rules, path: []const u8, source: [:0]const u8) ![]const []const u8 {
    var list: std.ArrayList(Violation) = .empty;
    _ = try checkFile(a, rules, path, source, &list);
    var keys: std.ArrayList([]const u8) = .empty;
    for (list.items) |v| try keys.append(a, try std.fmt.allocPrint(a, "{s} {s} → {s} @{d}", .{ v.rule, v.src, v.target, v.line }));
    return keys.items;
}

fn expectKeys(got: []const []const u8, want: []const []const u8) !void {
    if (got.len != want.len) {
        for (got) |g| std.debug.print("got: {s}\n", .{g});
        return error.TestUnexpectedResult;
    }
    for (want, got) |w, g| try testing.expectEqualStrings(w, g);
}

test "checkFile: core importing zenit ui, a feature view and shared ui" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const rules = try rules_mod.loadEmbeddedForTest(a);
    const src =
        \\const std = @import("std");
        \\const ui = @import("ui");
        \\const View = @import("../features/files/view/file_workspace_view.zig");
        \\const theme = @import("../shared/ui/theme/app_theme.zig");
        \\const paths = @import("../config/paths.zig");
        \\const weird = @import("not_a_module");
        \\test "ok in test" { _ = @import("../shared/testing/data_directory.zig"); }
    ;
    const got = try checkSource(a, &rules, "src/host/file_workspace_controller.zig", src);
    try expectKeys(got, &.{
        "layer:core->zenit_ui src/host/file_workspace_controller.zig → ui @2",
        "layer:core->view src/host/file_workspace_controller.zig → src/features/files/view/file_workspace_view.zig @3",
        "layer:core->shared_ui src/host/file_workspace_controller.zig → src/shared/ui/theme/app_theme.zig @4",
        "unclassified-module src/host/file_workspace_controller.zig → not_a_module @6",
    });
}

test "checkFile: test files are relaxed but cross-feature still applies" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const rules = try rules_mod.loadEmbeddedForTest(a);
    const src =
        \\const host = @import("../host/settings_host.zig");
        \\const kit = @import("../../../shared/testing/ui_kit.zig");
        \\const other = @import("../../ai/model/state.zig");
        \\const facade = @import("../../ai/mod.zig");
    ;
    const got = try checkSource(a, &rules, "src/features/settings/tests/host_tests.zig", src);
    try expectKeys(got, &.{"cross-feature src/features/settings/tests/host_tests.zig → src/features/ai/model/state.zig @3"});
}

test "checkFile: identifier rules on view_model and view (and skipped in tests)" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const rules = try rules_mod.loadEmbeddedForTest(a);
    const vm =
        \\const ui = @import("ui");
        \\pub const Vm = struct { title: *ui.Signal([]const u8), root: ?*ui.Node = null };
        \\fn bad(cx: *ui.Cx) void { _ = cx; }
        \\test "fixture" { var n: ui.Node = undefined; _ = &n; }
    ;
    try expectKeys(try checkSource(a, &rules, "src/features/settings/model/view_model.zig", vm), &.{
        "ident:view_model-reactive-subset src/features/settings/model/view_model.zig → ui.Node @2",
        "ident:view_model-reactive-subset src/features/settings/model/view_model.zig → ui.Cx @3",
    });
    const view =
        \\const std = @import("std");
        \\const ui = @import("ui");
        \\const host = @import("../host/settings_host.zig");
        \\fn spawn() void { _ = std.Thread.spawn; _ = std.posix.getenv; }
    ;
    try expectKeys(try checkSource(a, &rules, "src/features/settings/view/save_bar.yix", view), &.{
        "layer:view->host src/features/settings/view/save_bar.yix → src/features/settings/host/settings_host.zig @3",
        "ident:view-no-io src/features/settings/view/save_bar.yix → std.Thread @4",
        "ident:view-no-io src/features/settings/view/save_bar.yix → std.posix @4",
    });
    // 当前布局：bmc_ikvm 的平铺 view_model.zig 也受该规则约束
    try expectKeys(try checkSource(a, &rules, "src/plugins/bmc_ikvm/view_model.zig", "const ui = @import(\"ui\");\nfn f(n: *ui.Node) void { _ = n; }\n"), &.{
        "ident:view_model-reactive-subset src/plugins/bmc_ikvm/view_model.zig → ui.Node @2",
    });
}

test "checkFile: production code does not read or rewrite node test ids (tests, previews and test-mode routes may)" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const rules = try rules_mod.loadEmbeddedForTest(a);
    const view =
        \\const ui = @import("ui");
        \\fn mount(n: *ui.Node) void { n.meta.ownership.meta.test_id = "ai.send"; }
        \\fn findTagged(n: *ui.Node, id: []const u8) ?*ui.Node {
        \\    if (n.meta.ownership.meta.test_id) |value| if (@import("std").mem.eql(u8, value, id)) return n;
        \\    return null;
        \\}
        \\fn rename(n: *ui.Node) void { n.frame_state.state_bits.flags.test_id_owned = true; }
        \\test "fixture" { _ = findTagged(undefined, "x"); _ = (@as(*ui.Node, undefined)).meta.ownership.meta.test_id; }
    ;
    try expectKeys(try checkSource(a, &rules, "src/features/ai/cards/view/x.zig", view), &.{
        "ident:no-test-id-read src/features/ai/cards/view/x.zig → meta.test_id @ findTagged @4",
        "ident:no-test-id-rewrite src/features/ai/cards/view/x.zig → flags.test_id_owned @ rename @7",
    });
    // A preview runner and a test-mode route may look nodes up by id.
    try expectKeys(try checkSource(a, &rules, "src/features/ai/cards/preview/x_runner.zig", view), &.{});
    try expectKeys(try checkSource(a, &rules, "src/features/workspace/host/multiwindow_test_routes.zig", view), &.{});
}

test "checkFile: glossary terms in user-visible strings (comments, identifiers and tests are ignored)" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const rules = try rules_mod.loadEmbeddedForTest(a);
    const view =
        \\const std = @import("std");
        \\// 鉴权 in a comment is fine
        \\const jianquan_ok = 1;
        \\fn text() []const u8 { return "鉴权失败，请检查 API Key"; }
        \\test "fixture" { try std.testing.expect(std.mem.eql(u8, "鉴权", "鉴权")); }
    ;
    try expectKeys(try checkSource(a, &rules, "src/features/ai/view/fixture_view.zig", view), &.{
        "term:鉴权 src/features/ai/view/fixture_view.zig → 认证 @4",
    });
    // .yix template text is scanned line by line; `//` comment lines are skipped.
    const yix =
        \\const W = @import("ui").widgets;
        \\// 新建连接（旧说法，注释里不算）
        \\pub fn V() View { return <text>新建连接</text>; }
    ;
    try expectKeys(try checkSource(a, &rules, "src/features/shell/view/fixture.yix", yix), &.{
        "term:新建连接 src/features/shell/view/fixture.yix → 新建主机 @3",
    });
    // Test files and preview runners are not user-visible copy.
    try expectKeys(try checkSource(a, &rules, "src/features/ai/tests/fixture_tests.zig", "const s = \"鉴权\";\n"), &.{});
}

test "checkFile: shortcut text in views must come from the shortcut router" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const rules = try rules_mod.loadEmbeddedForTest(a);
    const view =
        \\const std = @import("std");
        \\// ⌘W in a comment is fine
        \\fn tip() []const u8 { return "关闭页签 · ⌘W"; }
        \\fn shifted() []const u8 { return "⇧⌘B"; }
        \\test "fixture" { try std.testing.expect(std.mem.eql(u8, "⌘W", "⌘W")); }
    ;
    try expectKeys(try checkSource(a, &rules, "src/features/workspace/view/fixture_view.zig", view), &.{
        "shortcut-text:⌘ src/features/workspace/view/fixture_view.zig → shortcut_router.hint / shortcut_glyphs @3",
        "shortcut-text:⌘ src/features/workspace/view/fixture_view.zig → shortcut_router.hint / shortcut_glyphs @4",
        "shortcut-text:⇧ src/features/workspace/view/fixture_view.zig → shortcut_router.hint / shortcut_glyphs @4",
    });
    // The router and the shared formatter are the one source.
    try expectKeys(try checkSource(a, &rules, "src/features/shell/model/shortcut_router.zig", "const s = \"⌘\";\n"), &.{});
}

test "checkFile: byte units in user-visible strings must be IEC (KiB / MiB, units-iec)" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const rules = try rules_mod.loadEmbeddedForTest(a);
    const view =
        \\const std = @import("std");
        \\// 12 MB/s in a comment is fine
        \\fn speed() []const u8 { return "12.4 MB/s"; }
        \\fn size() []const u8 { return "上限 64 KB"; }
        \\fn unit() []const u8 { return "MB"; }
        \\fn fine() []const u8 { return "64 KiB · 1.5 MiB · 2 GiB · 8 KiB/s · 3 MiB/s · KiB"; }
        \\test "fixture" { try std.testing.expect(std.mem.eql(u8, "1 MB", "1 MB")); }
    ;
    try expectKeys(try checkSource(a, &rules, "src/features/transfer/view/fixture_view.zig", view), &.{
        "term: KB src/features/transfer/view/fixture_view.zig → KiB（shared/base/format） @4",
        "term: MB src/features/transfer/view/fixture_view.zig → MiB（shared/base/format） @3",
        "term:MB/s src/features/transfer/view/fixture_view.zig → MiB/s（shared/base/format） @3",
        "term:\"MB\" src/features/transfer/view/fixture_view.zig → \"MiB\"（shared/base/format） @5",
    });
    const yix =
        \\// 1 MB in a comment line
        \\pub fn V() View { return <text>已传 3 MB · 2 MiB/s</text>; }
    ;
    try expectKeys(try checkSource(a, &rules, "src/features/transfer/view/fixture.yix", yix), &.{
        "term: MB src/features/transfer/view/fixture.yix → MiB（shared/base/format） @2",
    });
}

test "terms: allow list is per file glob and per term" {
    const allow = [_]rules_mod.TermAllow{.{ .file = "src/plugins/*/editor.zig", .term = "在线", .reason = "fixture" }};
    const terms: rules_mod.Terms = .{ .allow = &allow };
    try testing.expect(terms.allowed("src/plugins/remote/editor.zig", "在线"));
    try testing.expect(!terms.allowed("src/plugins/remote/editor.zig", "鉴权"));
    try testing.expect(!terms.allowed("src/features/shell/view/a.zig", "在线"));
}

test "checkFile: unclassified source and target" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const rules = try rules_mod.loadEmbeddedForTest(a);
    try expectKeys(try checkSource(a, &rules, "src/features/settings/stray.zig", "const x = 1;"), &.{"unclassified-source src/features/settings/stray.zig → - @0"});
    try expectKeys(try checkSource(a, &rules, "src/features/settings/view/a.zig", "const v = @import(\"../../../../vendor/x.zig\");"), &.{"unclassified-target src/features/settings/view/a.zig → vendor/x.zig @1"});
}
