//! relocate：P1 目录搬迁的一次性工具（docs/ui-revamp/ARCHITECTURE_PLAN.md §6.2 P1 第 2 条）。P6 删除。
//!
//!   relocate (--package NAME... | --all) [--dry-run] [--map PATH] [--report PATH] [--verbose]
//!
//! 经 `zig build relocate -Drelocate-args="…"` 运行，cwd 为仓库根。输入只有 move-map
//! （默认 docs/ui-revamp/move-map/_final.tsv，列 `old_path new_path layer package note`）。
//!
//! 做的事：
//! 1. 选出 `--package` 指定包（可重复）或 `--all` 的行，校验：旧路径被 git 跟踪、新路径不与现有文件冲突、
//!    新路径不重复；old == new 的行跳过。
//! 2. 计算改写：扫描 `src/**`、`tools/**`、`assets/**` 里被跟踪的 `.zig` / `.yix` / `.yss`（跳过生成孪生
//!    `_*.yix.zig` / `_*.yss.zig`，它们由 `zig build gen-yix` 重新生成），用 `std.zig.Tokenizer` 定位：
//!    - `@import("…")`（以 .zig/.zon/.yix/.yss 结尾的相对路径）；
//!    - `@embedFile(…)` 的参数：完整字面量按文件处理；`"dir/" ++ name` 这类拼接按目录前缀处理；
//!      参数里出现的标识符若在同文件有 `const X = "…";`，该字面量也按目录前缀处理；
//!    路径一律重算为“引用者新位置 → 目标新位置”的最短相对路径；入向与出向引用都覆盖。只替换字面量 token，
//!    其他字节不动。`build.zig` 里与某个旧路径完全相等的字符串字面量替换为新路径。
//! 3. 输出“其余对旧路径的引用”清单：全仓库被跟踪的文本文件里出现旧路径（仓库相对形式 `src/ui/x.zig`、
//!    含 `/` 的 src 相对形式 `ui/x.zig`、整体搬走的目录）且不属于上面已改写的位置，按 build.zig / e2e /
//!    scripts / docs / README / tools / vendor / src 字面量 / src 其他（注释等）/ src 生成物 / 其他 分类。
//! 4. 非 `--dry-run` 时：建目录、逐个 `git mv`，再把改写后的内容写到新位置。
//!
//! 退出码：0 成功；1 计划有问题（冲突、无法解析的目录前缀等，未做任何改动）；2 用法错误。
const std = @import("std");
const Allocator = std.mem.Allocator;

// ── move-map ─────────────────────────────────────────────────────────

pub const Row = struct { old: []const u8, new: []const u8, layer: []const u8, package: []const u8 };

/// 解析 TSV：跳过 `#` 注释行、空行与表头（第一列为 `old_path`）。
pub fn parseMap(arena: Allocator, text: []const u8) ![]Row {
    var rows: std.ArrayList(Row) = .empty;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (line.len == 0 or line[0] == '#') continue;
        var cols = std.mem.splitScalar(u8, line, '\t');
        const old = cols.next() orelse continue;
        const new = cols.next() orelse return error.MalformedMapLine;
        const layer = cols.next() orelse "";
        const package = cols.next() orelse "";
        if (std.mem.eql(u8, old, "old_path")) continue;
        try rows.append(arena, .{ .old = old, .new = new, .layer = layer, .package = package });
    }
    return rows.items;
}

// ── 路径运算（仓库相对路径，分隔符 `/`） ─────────────────────────────

pub fn dirname(path: []const u8) []const u8 {
    const i = std.mem.lastIndexOfScalar(u8, path, '/') orelse return "";
    return path[0..i];
}

fn splitSegments(arena: Allocator, path: []const u8) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var it = std.mem.tokenizeScalar(u8, path, '/');
    while (it.next()) |s| try out.append(arena, s);
    return out.items;
}

/// `base_dir` + 相对路径 `rel` 归一成仓库路径；绝对路径或越出仓库根返回 null。
pub fn resolve(arena: Allocator, base_dir: []const u8, rel: []const u8) !?[]const u8 {
    if (rel.len > 0 and rel[0] == '/') return null;
    var segs: std.ArrayList([]const u8) = .empty;
    for (try splitSegments(arena, base_dir)) |s| try segs.append(arena, s);
    var it = std.mem.tokenizeScalar(u8, rel, '/');
    while (it.next()) |s| {
        if (std.mem.eql(u8, s, ".")) continue;
        if (std.mem.eql(u8, s, "..")) {
            if (segs.items.len == 0) return null;
            _ = segs.pop();
            continue;
        }
        try segs.append(arena, s);
    }
    return try std.mem.join(arena, "/", segs.items);
}

/// 从目录 `from_dir` 指向目录 `to_dir` 的最短相对路径（不带结尾 `/`；两者相同时为空串）。
pub fn relativeDir(arena: Allocator, from_dir: []const u8, to_dir: []const u8) ![]const u8 {
    const a = try splitSegments(arena, from_dir);
    const b = try splitSegments(arena, to_dir);
    var k: usize = 0;
    while (k < a.len and k < b.len and std.mem.eql(u8, a[k], b[k])) k += 1;
    var out: std.ArrayList(u8) = .empty;
    for (k..a.len) |_| try out.appendSlice(arena, "../");
    for (b[k..], 0..) |s, i| {
        if (i > 0) try out.append(arena, '/');
        try out.appendSlice(arena, s);
    }
    if (out.items.len > 0 and out.items[out.items.len - 1] == '/') _ = out.pop();
    return out.items;
}

/// 从目录 `from_dir` 指向文件 `to_path` 的最短相对路径。
pub fn relativePath(arena: Allocator, from_dir: []const u8, to_path: []const u8) ![]const u8 {
    const d = try relativeDir(arena, from_dir, dirname(to_path));
    const base = to_path[if (std.mem.lastIndexOfScalar(u8, to_path, '/')) |i| i + 1 else 0..];
    if (d.len == 0) return arena.dupe(u8, base);
    return std.fmt.allocPrint(arena, "{s}/{s}", .{ d, base });
}

fn hasPathExtension(spec: []const u8) bool {
    for ([_][]const u8{ ".zig", ".zon", ".yix", ".yss" }) |ext| if (std.mem.endsWith(u8, spec, ext)) return true;
    return false;
}

pub fn isGeneratedTwin(path: []const u8) bool {
    const base = path[if (std.mem.lastIndexOfScalar(u8, path, '/')) |i| i + 1 else 0..];
    return base.len > 0 and base[0] == '_' and (std.mem.endsWith(u8, base, ".yix.zig") or std.mem.endsWith(u8, base, ".yss.zig"));
}

// ── 计划 ─────────────────────────────────────────────────────────────

pub const DirResult = union(enum) {
    /// 目录下没有文件搬走。
    same,
    /// 目录下所有文件按原相对结构搬到同一个新目录。
    moved: []const u8,
    /// 部分搬走，或搬到不同目录。`vacated` = 目录下不再留有任何文件。
    split: struct { vacated: bool },
};

pub const Plan = struct {
    arena: Allocator,
    /// 当前被 git 跟踪的路径，已排序。
    tracked: []const []const u8,
    tracked_set: std.StringHashMapUnmanaged(void) = .empty,
    /// 只含真正移动的行：旧路径 → 新路径。
    moves: std.StringHashMapUnmanaged([]const u8) = .empty,
    dir_cache: std.StringHashMapUnmanaged(DirResult) = .empty,

    pub fn init(arena: Allocator, tracked: []const []const u8) !Plan {
        var p: Plan = .{ .arena = arena, .tracked = tracked };
        for (tracked) |t| try p.tracked_set.put(arena, t, {});
        return p;
    }

    pub fn addMove(p: *Plan, old: []const u8, new: []const u8) !void {
        try p.moves.put(p.arena, old, new);
    }

    pub fn mapFile(p: *const Plan, path: []const u8) []const u8 {
        return p.moves.get(path) orelse path;
    }

    pub fn isMoved(p: *const Plan, path: []const u8) bool {
        return p.moves.contains(path);
    }

    pub fn exists(p: *const Plan, path: []const u8) bool {
        return p.tracked_set.contains(path);
    }

    fn lowerBound(p: *const Plan, key: []const u8) usize {
        var lo: usize = 0;
        var hi: usize = p.tracked.len;
        while (lo < hi) {
            const mid = (lo + hi) / 2;
            if (std.mem.order(u8, p.tracked[mid], key) == .lt) lo = mid + 1 else hi = mid;
        }
        return lo;
    }

    pub fn mapDir(p: *Plan, dir: []const u8) !DirResult {
        if (p.dir_cache.get(dir)) |r| return r;
        const prefix = try std.fmt.allocPrint(p.arena, "{s}/", .{dir});
        var any_moved = false;
        var any_stays = false;
        var target: ?[]const u8 = null;
        var consistent = true;
        var i = p.lowerBound(prefix);
        while (i < p.tracked.len and std.mem.startsWith(u8, p.tracked[i], prefix)) : (i += 1) {
            const old = p.tracked[i];
            const new = p.moves.get(old) orelse {
                any_stays = true;
                continue;
            };
            any_moved = true;
            const rel = old[prefix.len..];
            if (!std.mem.endsWith(u8, new, rel) or new.len == rel.len or new[new.len - rel.len - 1] != '/') {
                consistent = false;
                continue;
            }
            const nd = new[0 .. new.len - rel.len - 1];
            if (target) |t| {
                if (!std.mem.eql(u8, t, nd)) consistent = false;
            } else target = nd;
        }
        const r: DirResult = if (!any_moved)
            .same
        else if (!any_stays and consistent)
            .{ .moved = target.? }
        else
            .{ .split = .{ .vacated = !any_stays } };
        try p.dir_cache.put(p.arena, dir, r);
        return r;
    }
};

// ── 源码改写 ─────────────────────────────────────────────────────────

pub const Problem = struct { line: u32, message: []const u8 };

pub const Range = struct { start: usize, end: usize };

pub const Rewrite = struct {
    /// 改写后的内容；没有改动时为 null。
    content: ?[]const u8,
    edits: usize,
    /// 已按路径处理过的字面量 token 范围（报告“其余引用”时排除）。
    handled: []const Range,
    /// 其他（未处理的）字符串字面量 token 范围。
    literals: []const Range,
    problems: []const Problem,
};

const Tok = struct { tag: std.zig.Token.Tag, start: usize, end: usize };

const Kind = enum { import, embed_file, prefix };

const Edit = struct { start: usize, end: usize, text: []const u8 };

fn lineOf(source: []const u8, offset: usize) u32 {
    return @intCast(std.mem.count(u8, source[0..offset], "\n") + 1);
}

const Rewriter = struct {
    arena: Allocator,
    plan: *Plan,
    source: []const u8,
    cur: []const u8,
    new: []const u8,
    edits: std.ArrayList(Edit) = .empty,
    handled: std.ArrayList(Range) = .empty,
    problems: std.ArrayList(Problem) = .empty,

    fn problem(r: *Rewriter, offset: usize, comptime fmt: []const u8, args: anytype) !void {
        try r.problems.append(r.arena, .{ .line = lineOf(r.source, offset), .message = try std.fmt.allocPrint(r.arena, fmt, args) });
    }

    fn literal(r: *Rewriter, t: Tok, kind: Kind) !void {
        const raw = r.source[t.start..t.end];
        const value = std.zig.string_literal.parseAlloc(r.arena, raw) catch return;
        if (kind == .import and !hasPathExtension(value)) return; // 具名模块
        try r.handled.append(r.arena, .{ .start = t.start, .end = t.end });
        const cur_dir = dirname(r.cur);
        const new_dir = dirname(r.new);
        const replacement: []const u8 = switch (kind) {
            .import, .embed_file => blk: {
                if (kind == .embed_file and value.len > 0 and value[value.len - 1] == '/') break :blk try r.prefixValue(t, value, cur_dir, new_dir) orelse return;
                const target = try resolve(r.arena, cur_dir, value) orelse {
                    try r.problem(t.start, "路径越出仓库：{s}", .{value});
                    return;
                };
                if (!r.plan.exists(target)) try r.problem(t.start, "引用的文件不存在（搬迁前就无法解析）：{s} → {s}", .{ value, target });
                if (!r.plan.isMoved(target) and std.mem.eql(u8, r.cur, r.new)) return;
                break :blk try relativePath(r.arena, new_dir, r.plan.mapFile(target));
            },
            .prefix => try r.prefixValue(t, value, cur_dir, new_dir) orelse return,
        };
        if (std.mem.eql(u8, replacement, value)) return;
        if (std.mem.indexOfAny(u8, replacement, "\"\\\n") != null) {
            try r.problem(t.start, "新路径含需要转义的字符：{s}", .{replacement});
            return;
        }
        try r.edits.append(r.arena, .{ .start = t.start, .end = t.end, .text = try std.fmt.allocPrint(r.arena, "\"{s}\"", .{replacement}) });
    }

    /// 目录前缀：`dir/part` 中 `dir` 按目录映射，`part`（可为空）原样保留。
    fn prefixValue(r: *Rewriter, t: Tok, value: []const u8, cur_dir: []const u8, new_dir: []const u8) !?[]const u8 {
        const cut = std.mem.lastIndexOfScalar(u8, value, '/');
        const dpart = if (cut) |c| value[0..c] else "";
        const tail = if (cut) |c| value[c + 1 ..] else value;
        const dir = try resolve(r.arena, cur_dir, dpart) orelse {
            try r.problem(t.start, "目录前缀越出仓库：{s}", .{value});
            return null;
        };
        const mapped: []const u8 = switch (try r.plan.mapDir(dir)) {
            .same => dir,
            .moved => |nd| nd,
            .split => {
                try r.problem(t.start, "目录前缀 {s}（{s}）下的文件被拆到不同位置，无法整体改写", .{ value, dir });
                return null;
            },
        };
        if (std.mem.eql(u8, mapped, dir) and std.mem.eql(u8, cur_dir, new_dir)) return value;
        const rel = try relativeDir(r.arena, new_dir, mapped);
        if (cut == null) {
            if (rel.len == 0) return value;
            return try std.fmt.allocPrint(r.arena, "{s}/{s}", .{ rel, tail });
        }
        if (rel.len == 0) return if (tail.len == 0) "./" else tail;
        return try std.fmt.allocPrint(r.arena, "{s}/{s}", .{ rel, tail });
    }
};

/// 计算一个源文件（当前位置 `cur`，搬迁后位置 `new`）的改写。
pub fn rewriteSource(arena: Allocator, plan: *Plan, cur: []const u8, new: []const u8, source: [:0]const u8) !Rewrite {
    var toks: std.ArrayList(Tok) = .empty;
    var tokenizer = std.zig.Tokenizer.init(source);
    while (true) {
        const t = tokenizer.next();
        if (t.tag == .eof) break;
        try toks.append(arena, .{ .tag = t.tag, .start = t.loc.start, .end = t.loc.end });
    }
    const ts = toks.items;
    var r: Rewriter = .{ .arena = arena, .plan = plan, .source = source, .cur = cur, .new = new };
    var embed_idents: std.StringHashMapUnmanaged(void) = .empty;

    var i: usize = 0;
    while (i < ts.len) : (i += 1) {
        const t = ts[i];
        if (t.tag != .builtin) continue;
        const name = source[t.start..t.end];
        if (std.mem.eql(u8, name, "@import")) {
            if (i + 3 < ts.len and ts[i + 1].tag == .l_paren and ts[i + 2].tag == .string_literal and ts[i + 3].tag == .r_paren)
                try r.literal(ts[i + 2], .import);
            continue;
        }
        if (!std.mem.eql(u8, name, "@embedFile")) continue;
        if (i + 1 >= ts.len or ts[i + 1].tag != .l_paren) continue;
        var depth: usize = 0;
        var j = i + 1;
        while (j < ts.len) : (j += 1) {
            switch (ts[j].tag) {
                .l_paren => depth += 1,
                .r_paren => {
                    depth -= 1;
                    if (depth == 0) break;
                },
                else => {},
            }
        }
        const args = ts[i + 2 .. @min(j, ts.len)];
        if (args.len == 1 and args[0].tag == .string_literal) {
            try r.literal(args[0], .embed_file);
        } else if (args.len > 1) {
            if (args[0].tag == .string_literal and args[1].tag == .plus_plus) try r.literal(args[0], .prefix);
            for (args, 0..) |a, k| {
                if (a.tag != .identifier) continue;
                const near_concat = (k + 1 < args.len and args[k + 1].tag == .plus_plus) or (k > 0 and args[k - 1].tag == .plus_plus);
                if (near_concat) try embed_idents.put(arena, source[a.start..a.end], {});
            }
        }
        i = j;
    }
    // `const fixture_path = "dir/";` 之后被 `@embedFile(fixture_path ++ "x")` 使用。
    if (embed_idents.count() > 0) {
        var k: usize = 0;
        while (k + 4 < ts.len) : (k += 1) {
            if (ts[k].tag != .keyword_const or ts[k + 1].tag != .identifier or ts[k + 2].tag != .equal or ts[k + 3].tag != .string_literal) continue;
            if (ts[k + 4].tag != .semicolon) continue;
            if (!embed_idents.contains(source[ts[k + 1].start..ts[k + 1].end])) continue;
            try r.literal(ts[k + 3], .prefix);
        }
    }

    var literals: std.ArrayList(Range) = .empty;
    for (ts) |t| {
        if (t.tag != .string_literal and t.tag != .multiline_string_literal_line) continue;
        var is_handled = false;
        for (r.handled.items) |h| if (h.start == t.start) {
            is_handled = true;
        };
        if (!is_handled) try literals.append(arena, .{ .start = t.start, .end = t.end });
    }

    var content: ?[]const u8 = null;
    if (r.edits.items.len > 0) {
        std.mem.sort(Edit, r.edits.items, {}, struct {
            fn lt(_: void, a: Edit, b: Edit) bool {
                return a.start < b.start;
            }
        }.lt);
        var out: std.ArrayList(u8) = .empty;
        var pos: usize = 0;
        for (r.edits.items) |e| {
            try out.appendSlice(arena, source[pos..e.start]);
            try out.appendSlice(arena, e.text);
            pos = e.end;
        }
        try out.appendSlice(arena, source[pos..]);
        content = out.items;
    }
    return .{ .content = content, .edits = r.edits.items.len, .handled = r.handled.items, .literals = literals.items, .problems = r.problems.items };
}

/// build.zig：与某个旧路径完全相等的字符串字面量换成新路径。
pub fn rewriteBuildScript(arena: Allocator, plan: *const Plan, source: [:0]const u8, handled: *std.ArrayList(Range)) !?[]const u8 {
    var tokenizer = std.zig.Tokenizer.init(source);
    var out: std.ArrayList(u8) = .empty;
    var pos: usize = 0;
    var changed = false;
    while (true) {
        const t = tokenizer.next();
        if (t.tag == .eof) break;
        if (t.tag != .string_literal) continue;
        const value = std.zig.string_literal.parseAlloc(arena, source[t.loc.start..t.loc.end]) catch continue;
        const new = plan.moves.get(value) orelse continue;
        try handled.append(arena, .{ .start = t.loc.start, .end = t.loc.end });
        try out.appendSlice(arena, source[pos..t.loc.start]);
        try out.print(arena, "\"{s}\"", .{new});
        pos = t.loc.end;
        changed = true;
    }
    if (!changed) return null;
    try out.appendSlice(arena, source[pos..]);
    return out.items;
}

// ── 其余引用清单 ─────────────────────────────────────────────────────

/// `src_relative`：去掉 `src/` 的形式，只在 token 开头或紧跟 `./`、`../` 时算命中（避免误认 vendor/zenit/src/ui/…）。
pub const Needle = struct { old: []const u8, new: []const u8, is_dir: bool, src_relative: bool = false };

pub const Hit = struct { start: usize, end: usize, needle: Needle };

fn isPathChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_' or c == '-' or c == '.' or c == '/';
}

/// 在文本里找旧路径：按“路径字符”切 token，在每个段边界上取最长匹配。
pub fn findHits(arena: Allocator, needles: *const std.StringHashMapUnmanaged(Needle), text: []const u8) ![]Hit {
    var hits: std.ArrayList(Hit) = .empty;
    var i: usize = 0;
    while (i < text.len) {
        if (!isPathChar(text[i])) {
            i += 1;
            continue;
        }
        const start = i;
        while (i < text.len and isPathChar(text[i])) i += 1;
        var end = i;
        while (end > start and text[end - 1] == '.') end -= 1;
        const tok = text[start..end];
        var p: usize = 0;
        while (p < tok.len) {
            var best: ?Hit = null;
            // src 相对形式只认 token 开头，或前一段是 `.` / `..`
            const prev_seg = if (p == 0) "" else tok[if (std.mem.lastIndexOfScalar(u8, tok[0 .. p - 1], '/')) |k| k + 1 else 0 .. p - 1];
            const relative_ok = p == 0 or std.mem.eql(u8, prev_seg, ".") or std.mem.eql(u8, prev_seg, "..");
            var q = p;
            while (q <= tok.len) : (q += 1) {
                if (q != tok.len and tok[q] != '/') continue;
                if (q > p) if (needles.get(tok[p..q])) |n| {
                    if (!n.src_relative or relative_ok) best = .{ .start = start + p, .end = start + q, .needle = n };
                };
            }
            if (best) |b| {
                try hits.append(arena, b);
                p = b.end - start;
            } else {
                const next = std.mem.indexOfScalarPos(u8, tok, p, '/') orelse break;
                p = next + 1;
            }
        }
    }
    return hits.items;
}

pub const Category = enum {
    build_zig,
    e2e,
    scripts,
    docs,
    readme,
    tools,
    vendor,
    src_literal,
    src_other,
    src_generated,
    other,

    pub fn label(c: Category) []const u8 {
        return switch (c) {
            .build_zig => "build.zig",
            .e2e => "e2e",
            .scripts => "scripts",
            .docs => "docs",
            .readme => "README",
            .tools => "tools",
            .vendor => "vendor",
            .src_literal => "src 字符串字面量",
            .src_other => "src 注释/非 Zig 文件",
            .src_generated => "src 生成孪生（gen-yix 重写）",
            .other => "其他",
        };
    }
};

fn categoryOf(path: []const u8) Category {
    if (std.mem.eql(u8, path, "build.zig")) return .build_zig;
    if (std.mem.startsWith(u8, path, "e2e/")) return .e2e;
    if (std.mem.startsWith(u8, path, "scripts/")) return .scripts;
    if (std.mem.startsWith(u8, path, "docs/")) return .docs;
    if (std.mem.startsWith(u8, path, "README")) return .readme;
    if (std.mem.startsWith(u8, path, "tools/")) return .tools;
    if (std.mem.startsWith(u8, path, "vendor/")) return .vendor;
    if (std.mem.startsWith(u8, path, "src/")) return if (isGeneratedTwin(path)) .src_generated else .src_other;
    return .other;
}

// ── 主流程 ───────────────────────────────────────────────────────────

const Options = struct {
    map_path: []const u8 = "docs/ui-revamp/move-map/_final.tsv",
    packages: []const []const u8 = &.{},
    all: bool = false,
    dry_run: bool = false,
    report_path: ?[]const u8 = null,
    verbose: bool = false,
};

const Ctx = struct { arena: Allocator, io: std.Io, out: *std.Io.Writer };

pub fn main(init: std.process.Init) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const args = try init.minimal.args.toSlice(arena);
    var buf: [64 * 1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &buf);
    const code = run(.{ .arena = arena, .io = init.io, .out = &stdout.interface }, args[1..]) catch |err| blk: {
        stdout.interface.print("relocate: 错误 {s}\n", .{@errorName(err)}) catch {};
        break :blk 2;
    };
    stdout.interface.flush() catch {};
    if (code != 0) std.process.exit(code);
}

fn usage(ctx: Ctx) u8 {
    ctx.out.writeAll(
        \\usage: relocate (--package NAME... | --all) [--dry-run] [--map PATH] [--report PATH] [--verbose]
        \\
    ) catch {};
    return 2;
}

fn gitLines(ctx: Ctx, argv: []const []const u8) ![]const []const u8 {
    const res = try std.process.run(ctx.arena, ctx.io, .{ .argv = argv });
    if (!res.term.success()) {
        try ctx.out.print("命令失败：{s}\n{s}\n", .{ argv[1], res.stderr });
        return error.GitFailed;
    }
    var out: std.ArrayList([]const u8) = .empty;
    var it = std.mem.splitScalar(u8, res.stdout, 0);
    while (it.next()) |s| if (s.len > 0) try out.append(ctx.arena, s);
    return out.items;
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

const Edited = struct { cur: []const u8, new: []const u8, content: []const u8, edits: usize };

fn run(ctx: Ctx, args: []const [:0]const u8) !u8 {
    var opts: Options = .{};
    var packages: std.ArrayList([]const u8) = .empty;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const a: []const u8 = args[i];
        if (std.mem.eql(u8, a, "--all")) {
            opts.all = true;
        } else if (std.mem.eql(u8, a, "--dry-run")) {
            opts.dry_run = true;
        } else if (std.mem.eql(u8, a, "--verbose")) {
            opts.verbose = true;
        } else if (std.mem.eql(u8, a, "--package") or std.mem.eql(u8, a, "--map") or std.mem.eql(u8, a, "--report")) {
            if (i + 1 >= args.len) return usage(ctx);
            i += 1;
            const v: []const u8 = args[i];
            if (std.mem.eql(u8, a, "--package")) try packages.append(ctx.arena, v) else if (std.mem.eql(u8, a, "--map")) opts.map_path = v else opts.report_path = v;
        } else return usage(ctx);
    }
    opts.packages = packages.items;
    if (opts.all == (opts.packages.len > 0)) return usage(ctx);

    const map_text = try std.Io.Dir.cwd().readFileAlloc(ctx.io, opts.map_path, ctx.arena, .limited(16 * 1024 * 1024));
    const rows = try parseMap(ctx.arena, map_text);
    const tracked = try gitLines(ctx, &.{ "git", "ls-files", "-z" });
    std.mem.sort([]const u8, @constCast(tracked), {}, lessThan);
    var plan = try Plan.init(ctx.arena, tracked);

    // 1. 选行并校验
    var bad: usize = 0;
    var selected: std.ArrayList(Row) = .empty;
    var new_seen: std.StringHashMapUnmanaged(void) = .empty;
    for (rows) |row| {
        if (!opts.all) {
            var hit = false;
            for (opts.packages) |p| if (std.mem.eql(u8, p, row.package)) {
                hit = true;
            };
            if (!hit) continue;
        }
        if (std.mem.eql(u8, row.old, row.new)) continue;
        if (!plan.exists(row.old)) {
            try ctx.out.print("问题：旧路径未被 git 跟踪（已搬过？）：{s}\n", .{row.old});
            bad += 1;
            continue;
        }
        if (new_seen.contains(row.new)) {
            try ctx.out.print("问题：新路径重复：{s}\n", .{row.new});
            bad += 1;
            continue;
        }
        try new_seen.put(ctx.arena, row.new, {});
        try selected.append(ctx.arena, row);
        try plan.addMove(row.old, row.new);
    }
    for (selected.items) |row| {
        if (plan.exists(row.new) and !plan.isMoved(row.new)) {
            try ctx.out.print("问题：新路径与留在原地的文件冲突：{s}\n", .{row.new});
            bad += 1;
        }
        // Yix/Yss 源文件与孪生必须同目录
        const base = row.old[if (std.mem.lastIndexOfScalar(u8, row.old, '/')) |k| k + 1 else 0..];
        if (std.mem.endsWith(u8, base, ".yss") or std.mem.endsWith(u8, base, ".yix")) {
            const twin = try std.fmt.allocPrint(ctx.arena, "{s}/_{s}.zig", .{ dirname(row.old), base });
            if (plan.exists(twin)) {
                const twin_new = plan.mapFile(twin);
                if (!std.mem.eql(u8, dirname(twin_new), dirname(row.new))) {
                    try ctx.out.print("问题：{s} 与孪生 {s} 搬迁后不在同一目录\n", .{ row.old, twin });
                    bad += 1;
                }
            }
        }
    }
    const pkg_label = if (opts.all) "--all" else try std.mem.join(ctx.arena, ",", opts.packages);
    try ctx.out.print("relocate {s}：选中 {d} 个文件搬迁{s}\n", .{ pkg_label, selected.items.len, if (opts.dry_run) "（dry-run）" else "" });

    // 2. 源码改写
    var edited: std.ArrayList(Edited) = .empty;
    var handled_by_file: std.StringHashMapUnmanaged([]const Range) = .empty;
    var literals_by_file: std.StringHashMapUnmanaged([]const Range) = .empty;
    var total_edits: usize = 0;
    var problems: usize = 0;
    for (tracked) |path| {
        const in_scope = std.mem.startsWith(u8, path, "src/") or std.mem.startsWith(u8, path, "tools/") or std.mem.startsWith(u8, path, "assets/");
        if (!in_scope) continue;
        if (!(std.mem.endsWith(u8, path, ".zig") or std.mem.endsWith(u8, path, ".yix") or std.mem.endsWith(u8, path, ".yss"))) continue;
        if (isGeneratedTwin(path)) continue;
        const source = try std.Io.Dir.cwd().readFileAllocOptions(ctx.io, path, ctx.arena, .limited(64 * 1024 * 1024), .of(u8), 0);
        const new = plan.mapFile(path);
        const rw = try rewriteSource(ctx.arena, &plan, path, new, source);
        try handled_by_file.put(ctx.arena, path, rw.handled);
        try literals_by_file.put(ctx.arena, path, rw.literals);
        for (rw.problems) |p| {
            // 搬迁前就存在、且与本次搬迁无关的无法解析引用只在 --verbose 时显示
            const relevant = plan.isMoved(path) or std.mem.indexOf(u8, p.message, "不存在") == null;
            if (relevant or opts.verbose) try ctx.out.print("问题：{s}:{d} {s}\n", .{ path, p.line, p.message });
            if (relevant) problems += 1;
        }
        if (rw.content) |c| {
            try edited.append(ctx.arena, .{ .cur = path, .new = new, .content = c, .edits = rw.edits });
            total_edits += rw.edits;
        } else if (plan.isMoved(path)) {
            try edited.append(ctx.arena, .{ .cur = path, .new = new, .content = source, .edits = 0 });
        }
    }
    var build_handled: std.ArrayList(Range) = .empty;
    const build_source = try std.Io.Dir.cwd().readFileAllocOptions(ctx.io, "build.zig", ctx.arena, .limited(16 * 1024 * 1024), .of(u8), 0);
    const build_new = try rewriteBuildScript(ctx.arena, &plan, build_source, &build_handled);
    try handled_by_file.put(ctx.arena, "build.zig", build_handled.items);
    bad += problems;

    var files_changed: usize = 0;
    for (edited.items) |e| if (e.edits > 0) {
        files_changed += 1;
    };
    try ctx.out.print("路径改写：{d} 个文件、{d} 处字面量；build.zig {d} 处\n", .{ files_changed, total_edits, build_handled.items.len });
    if (opts.verbose) for (edited.items) |e| if (e.edits > 0) try ctx.out.print("  改写 {s}{s}{s}：{d} 处\n", .{ e.cur, if (std.mem.eql(u8, e.cur, e.new)) "" else " → ", if (std.mem.eql(u8, e.cur, e.new)) "" else e.new, e.edits });

    // 3. 其余引用清单
    try reportReferences(ctx, &plan, opts, &handled_by_file, &literals_by_file);

    if (bad > 0) {
        try ctx.out.print("计划有 {d} 个问题，未做任何改动。\n", .{bad});
        return 1;
    }
    if (opts.dry_run) {
        for (selected.items) |row| if (opts.verbose) try ctx.out.print("  搬迁 {s} → {s}\n", .{ row.old, row.new });
        try ctx.out.print("dry-run：未改动任何文件。\n", .{});
        return 0;
    }

    // 4. 执行
    for (selected.items) |row| {
        const parent = dirname(row.new);
        if (parent.len > 0) try std.Io.Dir.cwd().createDirPath(ctx.io, parent);
        const res = try std.process.run(ctx.arena, ctx.io, .{ .argv = &.{ "git", "mv", "--", row.old, row.new } });
        if (!res.term.success()) {
            try ctx.out.print("git mv 失败：{s} → {s}\n{s}\n", .{ row.old, row.new, res.stderr });
            return 1;
        }
    }
    // git mv 不删搬空的目录：自下而上删掉空目录（非空的删除失败，忽略）。
    var emptied: usize = 0;
    for (selected.items) |row| {
        var d = dirname(row.old);
        while (d.len > 0 and !std.mem.eql(u8, d, "src")) : (d = dirname(d)) {
            std.Io.Dir.cwd().deleteDir(ctx.io, d) catch |err| switch (err) {
                error.FileNotFound => continue, // 已被同目录的前一行删掉，继续看上一级
                else => break, // 非空等：上一级必然也非空
            };
            emptied += 1;
        }
    }
    if (emptied > 0) try ctx.out.print("删除搬空的目录 {d} 个\n", .{emptied});
    for (edited.items) |e| {
        if (e.edits == 0) continue;
        try std.Io.Dir.cwd().writeFile(ctx.io, .{ .sub_path = e.new, .data = e.content });
    }
    if (build_new) |b| try std.Io.Dir.cwd().writeFile(ctx.io, .{ .sub_path = "build.zig", .data = b });
    try ctx.out.print("完成：搬迁 {d} 个文件，改写 {d} 个文件。下一步：zig build gen-yix（若搬动了 .yix/.yss），再手工同步上面的其余引用。\n", .{ selected.items.len, files_changed + @intFromBool(build_new != null) });
    return 0;
}

fn inRanges(ranges: []const Range, start: usize, end: usize) bool {
    for (ranges) |r| if (start >= r.start and end <= r.end) return true;
    return false;
}

fn reportReferences(
    ctx: Ctx,
    plan: *Plan,
    opts: Options,
    handled_by_file: *const std.StringHashMapUnmanaged([]const Range),
    literals_by_file: *const std.StringHashMapUnmanaged([]const Range),
) !void {
    // 旧路径 needle：文件的仓库形式与 src 相对形式（含 `/` 时），以及整体搬走/清空的目录。
    var needles: std.StringHashMapUnmanaged(Needle) = .empty;
    var it = plan.moves.iterator();
    while (it.next()) |kv| {
        const old = kv.key_ptr.*;
        const new = kv.value_ptr.*;
        try needles.put(ctx.arena, old, .{ .old = old, .new = new, .is_dir = false });
        if (std.mem.startsWith(u8, old, "src/") and std.mem.indexOfScalar(u8, old[4..], '/') != null)
            try needles.put(ctx.arena, old[4..], .{ .old = old, .new = new, .is_dir = false, .src_relative = true });
        var d = dirname(old);
        while (d.len > 0 and !std.mem.eql(u8, d, "src")) : (d = dirname(d)) {
            if (needles.contains(d)) continue;
            const r = try plan.mapDir(d);
            const new_dir: ?[]const u8 = switch (r) {
                .same => null,
                .moved => |nd| nd,
                .split => |s| if (s.vacated) "(拆散到多处)" else null,
            };
            if (new_dir) |nd| {
                try needles.put(ctx.arena, d, .{ .old = d, .new = nd, .is_dir = true });
                if (std.mem.startsWith(u8, d, "src/") and std.mem.indexOfScalar(u8, d[4..], '/') != null)
                    try needles.put(ctx.arena, d[4..], .{ .old = d, .new = nd, .is_dir = true, .src_relative = true });
            }
        }
    }

    var counts = std.EnumArray(Category, usize).initFill(0);
    var file_counts = std.EnumArray(Category, usize).initFill(0);
    var detail: std.Io.Writer.Allocating = .init(ctx.arena);
    var skipped_map: usize = 0;
    for (plan.tracked) |path| {
        if (std.mem.startsWith(u8, path, "docs/ui-revamp/move-map/")) {
            skipped_map += 1;
            continue;
        }
        const text = std.Io.Dir.cwd().readFileAlloc(ctx.io, path, ctx.arena, .limited(8 * 1024 * 1024)) catch continue;
        if (std.mem.indexOfScalar(u8, text[0..@min(text.len, 8000)], 0) != null) continue;
        const hits = try findHits(ctx.arena, &needles, text);
        if (hits.len == 0) continue;
        const handled = handled_by_file.get(path) orelse &.{};
        const literals = literals_by_file.get(path);
        var seen = std.EnumSet(Category).empty;
        for (hits) |h| {
            if (inRanges(handled, h.start, h.end)) continue;
            var cat = categoryOf(path);
            if (cat == .src_other) if (literals) |lits| if (inRanges(lits, h.start, h.end)) {
                cat = .src_literal;
            };
            counts.getPtr(cat).* += 1;
            seen.insert(cat);
            try detail.writer.print("{s}\t{s}:{d}\t{s}\t{s} -> {s}\n", .{ cat.label(), path, lineOf(text, h.start), text[h.start..h.end], h.needle.old, h.needle.new });
            if (cat == .src_literal or opts.verbose and cat != .vendor and cat != .docs)
                try ctx.out.print("  引用 [{s}] {s}:{d} {s}\n", .{ cat.label(), path, lineOf(text, h.start), text[h.start..h.end] });
        }
        for (std.enums.values(Category)) |c| if (seen.contains(c)) {
            file_counts.getPtr(c).* += 1;
        };
    }
    try ctx.out.print("其余对旧路径的引用（需手工同步；vendor 只列不改；docs/ui-revamp/move-map 下 {d} 个文件不扫）：\n", .{skipped_map});
    for (std.enums.values(Category)) |c| {
        if (counts.get(c) > 0) try ctx.out.print("  {s}: {d} 处，{d} 个文件\n", .{ c.label(), counts.get(c), file_counts.get(c) });
    }
    if (opts.report_path) |rp| {
        try std.Io.Dir.cwd().writeFile(ctx.io, .{ .sub_path = rp, .data = detail.written() });
        try ctx.out.print("  明细（分类\\t文件:行\\t命中\\t旧 -> 新）写入 {s}\n", .{rp});
    }
}

// ── 单测 ─────────────────────────────────────────────────────────────

const testing = std.testing;

fn testPlan(arena: Allocator, tracked: []const []const u8, moves: []const [2][]const u8) !Plan {
    const sorted = try arena.dupe([]const u8, tracked);
    std.mem.sort([]const u8, sorted, {}, lessThan);
    var p = try Plan.init(arena, sorted);
    for (moves) |m| try p.addMove(m[0], m[1]);
    return p;
}

fn rewriteForTest(arena: Allocator, plan: *Plan, cur: []const u8, source: [:0]const u8) ![]const u8 {
    const r = try rewriteSource(arena, plan, cur, plan.mapFile(cur), source);
    return r.content orelse source;
}

test "relocate path math: resolve, relativeDir, relativePath" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    try testing.expectEqualStrings("src/ui/app_theme.zig", (try resolve(a, "src", "ui/app_theme.zig")).?);
    try testing.expectEqualStrings("src/ui/app_theme.zig", (try resolve(a, "src/config", "../ui/./app_theme.zig")).?);
    try testing.expect((try resolve(a, "src", "../../x.zig")) == null);
    try testing.expect((try resolve(a, "src", "/abs.zig")) == null);
    try testing.expectEqualStrings("", try relativeDir(a, "src/ui", "src/ui"));
    try testing.expectEqualStrings("../../shared/ui/theme", try relativeDir(a, "src/features/settings", "src/shared/ui/theme"));
    try testing.expectEqualStrings("app_theme.zig", try relativePath(a, "src/shared/ui/theme", "src/shared/ui/theme/app_theme.zig"));
    try testing.expectEqualStrings("../../../shared/ui/theme/app_theme.zig", try relativePath(a, "src/features/settings/view", "src/shared/ui/theme/app_theme.zig"));
    try testing.expectEqualStrings("features/settings/view/x.zig", try relativePath(a, "src", "src/features/settings/view/x.zig"));
    try testing.expectEqualStrings("../root.zig", try relativePath(a, "src/ui", "src/root.zig"));
    try testing.expectEqualStrings("src/a.zig", try relativePath(a, "", "src/a.zig"));
}

test "relocate rewrites outgoing imports of a moved file and keeps other bytes" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var plan = try testPlan(a, &.{ "src/ui/a.zig", "src/ui/b.zig", "src/config/c.zig" }, &.{.{ "src/ui/a.zig", "src/features/f/view/a.zig" }});
    const out = try rewriteForTest(a, &plan, "src/ui/a.zig",
        \\const std = @import("std");
        \\const ui = @import("ui"); // 具名模块不动
        \\const b = @import("b.zig");
        \\const c =   @import( "../config/c.zig" );
        \\const s = "b.zig"; // 非 import 字面量不动
    );
    try testing.expectEqualStrings(
        \\const std = @import("std");
        \\const ui = @import("ui"); // 具名模块不动
        \\const b = @import("../../../ui/b.zig");
        \\const c =   @import( "../../../config/c.zig" );
        \\const s = "b.zig"; // 非 import 字面量不动
    , out);
}

test "relocate rewrites incoming imports and leaves unaffected files untouched" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var plan = try testPlan(a, &.{ "src/ui/a.zig", "src/ui/b.zig", "src/root.zig" }, &.{.{ "src/ui/a.zig", "src/features/f/view/a.zig" }});
    try testing.expectEqualStrings("const a = @import(\"../features/f/view/a.zig\");\nconst b = @import(\"b.zig\");",
        try rewriteForTest(a, &plan, "src/ui/b.zig", "const a = @import(\"a.zig\");\nconst b = @import(\"b.zig\");"));
    try testing.expectEqualStrings("pub const a = @import(\"features/f/view/a.zig\");",
        try rewriteForTest(a, &plan, "src/root.zig", "pub const a = @import(\"ui/a.zig\");"));
    const untouched = try rewriteSource(a, &plan, "src/ui/b.zig", "src/ui/b.zig", "const b = @import(\"b.zig\");");
    try testing.expect(untouched.content == null);
}

test "relocate handles same-basename files in different directories and renamed targets" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var plan = try testPlan(a, &.{ "src/ui/styles.zig", "src/ui/files/styles.zig", "src/ui/terminal_surface_tests.zig", "src/ui/terminal_surface.zig", "src/transfer_panel_tests.zig" }, &.{
        .{ "src/ui/styles.zig", "src/features/a/view/styles.zig" },
        .{ "src/ui/files/styles.zig", "src/features/files/view/styles.zig" },
        .{ "src/ui/terminal_surface_tests.zig", "src/features/terminal/tests/terminal_surface_view_tests.zig" },
        .{ "src/ui/terminal_surface.zig", "src/features/terminal/view/terminal_surface.zig" },
        .{ "src/transfer_panel_tests.zig", "src/tests_ui.zig" },
    });
    try testing.expectEqualStrings(
        "const x = @import(\"features/a/view/styles.zig\");const y = @import(\"features/files/view/styles.zig\");comptime { _ = @import(\"features/terminal/tests/terminal_surface_view_tests.zig\"); }",
        try rewriteForTest(a, &plan, "src/transfer_panel_tests.zig", "const x = @import(\"ui/styles.zig\");const y = @import(\"ui/files/styles.zig\");comptime { _ = @import(\"ui/terminal_surface_tests.zig\"); }"),
    );
    try testing.expectEqualStrings("const s = @import(\"../view/terminal_surface.zig\");",
        try rewriteForTest(a, &plan, "src/ui/terminal_surface_tests.zig", "const s = @import(\"terminal_surface.zig\");"));
}

test "relocate rewrites @embedFile literals, directory prefixes and const prefixes" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var plan = try testPlan(a, &.{
        "src/ui/host_os_assets.zig",  "src/ui/assets/host-os/a.svg", "src/ui/assets/host-os/b.rgba",
        "src/ui/donation_qr.zig",     "src/ui/assets/donation-qr.txt",
        "src/bmc_rfb_tests.zig",      "src/plugins/bmc/protocol/rfb_fixtures/x.z",
    }, &.{
        .{ "src/ui/host_os_assets.zig", "src/shared/ui/assets/host_os_assets.zig" },
        .{ "src/ui/assets/host-os/a.svg", "src/shared/ui/assets/host-os/a.svg" },
        .{ "src/ui/assets/host-os/b.rgba", "src/shared/ui/assets/host-os/b.rgba" },
        .{ "src/ui/donation_qr.zig", "src/shared/base/donation_qr.zig" },
        .{ "src/ui/assets/donation-qr.txt", "src/shared/ui/assets/donation-qr.txt" },
        .{ "src/bmc_rfb_tests.zig", "src/plugins/bmc/tests/bmc_rfb_tests.zig" },
    });
    try testing.expectEqualStrings(
        "fn svg(comptime name: []const u8) []const u8 { return @embedFile(\"host-os/\" ++ name ++ \".svg\"); }\nconst b = @embedFile(\"host-os/b.rgba\");",
        try rewriteForTest(a, &plan, "src/ui/host_os_assets.zig", "fn svg(comptime name: []const u8) []const u8 { return @embedFile(\"assets/host-os/\" ++ name ++ \".svg\"); }\nconst b = @embedFile(\"assets/host-os/b.rgba\");"),
    );
    try testing.expectEqualStrings("const q = @embedFile(\"../ui/assets/donation-qr.txt\");",
        try rewriteForTest(a, &plan, "src/ui/donation_qr.zig", "const q = @embedFile(\"assets/donation-qr.txt\");"));
    try testing.expectEqualStrings("const fixture_path = \"../protocol/rfb_fixtures/\";\nconst z = @embedFile(fixture_path ++ \"x.z\");\nconst other = \"plugins/bmc/protocol/rfb_fixtures/\";",
        try rewriteForTest(a, &plan, "src/bmc_rfb_tests.zig", "const fixture_path = \"plugins/bmc/protocol/rfb_fixtures/\";\nconst z = @embedFile(fixture_path ++ \"x.z\");\nconst other = \"plugins/bmc/protocol/rfb_fixtures/\";"));
}

test "relocate reports a directory prefix whose files are split" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var plan = try testPlan(a, &.{ "src/ui/x.zig", "src/ui/assets/a.svg", "src/ui/assets/b.svg" }, &.{.{ "src/ui/assets/a.svg", "src/shared/ui/assets/a.svg" }});
    const r = try rewriteSource(a, &plan, "src/ui/x.zig", "src/ui/x.zig", "const s = @embedFile(\"assets/\" ++ name);");
    try testing.expect(r.content == null);
    try testing.expectEqual(@as(usize, 1), r.problems.len);
}

test "relocate rewrites .yix and .yss imports with the tokenizer" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var plan = try testPlan(a, &.{ "src/ui/settings/styles.yss", "src/ui/settings/_styles.yss.zig", "src/ui/settings/rows.yix", "src/ui/vm.zig" }, &.{
        .{ "src/ui/settings/styles.yss", "src/features/settings/view/styles.yss" },
        .{ "src/ui/settings/_styles.yss.zig", "src/features/settings/view/_styles.yss.zig" },
        .{ "src/ui/settings/rows.yix", "src/features/settings/view/parts/rows.yix" },
    });
    const yix =
        \\const ui = @import("ui");
        \\const S = @import("styles.yss");
        \\const m = @import("../vm.zig");
        \\pub fn Row(label: []const u8 = "") View {
        \\    return (<row testId="settings.row" style={S.row}><text>it's {label} // not a comment</text></row>);
        \\}
    ;
    try testing.expectEqualStrings(
        \\const ui = @import("ui");
        \\const S = @import("../styles.yss");
        \\const m = @import("../../../../ui/vm.zig");
        \\pub fn Row(label: []const u8 = "") View {
        \\    return (<row testId="settings.row" style={S.row}><text>it's {label} // not a comment</text></row>);
        \\}
    , try rewriteForTest(a, &plan, "src/ui/settings/rows.yix", yix));
    try testing.expectEqualStrings("const S = @import(\"../features/settings/view/_styles.yss.zig\");",
        try rewriteForTest(a, &plan, "src/ui/vm.zig", "const S = @import(\"settings/_styles.yss.zig\");"));
}

test "relocate rewrites exact old paths in build.zig only" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var plan = try testPlan(a, &.{ "src/transfer_panel_tests.zig", "src/ui/theme/zerowork.tokens.json" }, &.{
        .{ "src/transfer_panel_tests.zig", "src/tests_ui.zig" },
        .{ "src/ui/theme/zerowork.tokens.json", "src/shared/ui/theme/zerowork.tokens.json" },
    });
    var handled: std.ArrayList(Range) = .empty;
    const out = (try rewriteBuildScript(a, &plan, "b.path(\"src/transfer_panel_tests.zig\"); b.path(\"src/ui/theme/zerowork.tokens.json\"); \"src/ui\"", &handled)).?;
    try testing.expectEqualStrings("b.path(\"src/tests_ui.zig\"); b.path(\"src/shared/ui/theme/zerowork.tokens.json\"); \"src/ui\"", out);
    try testing.expectEqual(@as(usize, 2), handled.items.len);
}

test "relocate finds remaining references at path segment boundaries" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var needles: std.StringHashMapUnmanaged(Needle) = .empty;
    try needles.put(a, "src/ui/app_theme.zig", .{ .old = "src/ui/app_theme.zig", .new = "n", .is_dir = false });
    try needles.put(a, "ui/app_theme.zig", .{ .old = "src/ui/app_theme.zig", .new = "n", .is_dir = false, .src_relative = true });
    try needles.put(a, "src/ui/assets", .{ .old = "src/ui/assets", .new = "d", .is_dir = true });
    const text = "see `src/ui/app_theme.zig`. also ../ui/app_theme.zig and src/ui/assets/host-os, not src/ui/app_theme.zigx or xsrc/ui/app_theme.zig";
    const hits = try findHits(a, &needles, text);
    try testing.expectEqual(@as(usize, 3), hits.len);
    try testing.expectEqualStrings("src/ui/app_theme.zig", text[hits[0].start..hits[0].end]);
    try testing.expectEqualStrings("ui/app_theme.zig", text[hits[1].start..hits[1].end]);
    try testing.expectEqualStrings("src/ui/assets", text[hits[2].start..hits[2].end]);
}

test "relocate parses the move-map TSV" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const rows = try parseMap(a, "old_path\tnew_path\tlayer\tpackage\tnote\n# c\nsrc/a.zig\tsrc/b/a.zig\tview\tshell\tx\n\nsrc/m.zig\tsrc/m.zig\troot\tno\t\n");
    try testing.expectEqual(@as(usize, 2), rows.len);
    try testing.expectEqualStrings("shell", rows[0].package);
    try testing.expectEqualStrings("src/b/a.zig", rows[0].new);
}

test "relocate classifies directories as same, moved or split" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var plan = try testPlan(a, &.{ "src/ui/a/x.svg", "src/ui/a/y/z.svg", "src/ui/b/x.svg", "src/ui/b/y.svg", "src/ui/c.zig" }, &.{
        .{ "src/ui/a/x.svg", "src/s/a/x.svg" },
        .{ "src/ui/a/y/z.svg", "src/s/a/y/z.svg" },
        .{ "src/ui/b/x.svg", "src/s/b/x.svg" },
        .{ "src/ui/b/y.svg", "src/t/y.svg" },
    });
    try testing.expectEqualStrings("src/s/a", (try plan.mapDir("src/ui/a")).moved);
    try testing.expect((try plan.mapDir("src/ui/b")).split.vacated);
    try testing.expect(!(try plan.mapDir("src/ui")).split.vacated);
    try testing.expect((try plan.mapDir("src/config")) == .same);
}
