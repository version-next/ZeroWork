//! 基于 `std.zig.Tokenizer` 的源码扫描：`@import`、标识符序列、`test` 块、字符串字面量。
//! `.yix` 也走同一个分词器：模板标签只会产生无关 token（见 README 的 V-9 小节）。
const std = @import("std");
const Token = std.zig.Token;

pub const Tok = struct {
    tag: Token.Tag,
    start: u32,
    end: u32,
    line: u32,
    /// 位于某个 `test` 块内部（含嵌套）。
    in_test: bool,
};

/// 分词并标注行号与 test 块范围。
pub fn tokenize(arena: std.mem.Allocator, source: [:0]const u8) ![]Tok {
    var list: std.ArrayList(Tok) = .empty;
    var tokenizer = std.zig.Tokenizer.init(source);
    var line: u32 = 1;
    var cursor: usize = 0;
    while (true) {
        const t = tokenizer.next();
        if (t.tag == .eof) break;
        line += @intCast(std.mem.count(u8, source[cursor..t.loc.start], "\n"));
        cursor = t.loc.start;
        try list.append(arena, .{ .tag = t.tag, .start = @intCast(t.loc.start), .end = @intCast(t.loc.end), .line = line, .in_test = false });
    }
    markTests(list.items);
    return list.items;
}

/// `test "name" {`、`test name {`、`test {` 后面的花括号区间标为 in_test。
fn markTests(toks: []Tok) void {
    var i: usize = 0;
    while (i < toks.len) : (i += 1) {
        if (toks[i].tag != .keyword_test) continue;
        var j = i + 1;
        if (j < toks.len and (toks[j].tag == .string_literal or toks[j].tag == .identifier)) j += 1;
        if (j >= toks.len or toks[j].tag != .l_brace) continue;
        var depth: usize = 0;
        var k = j;
        while (k < toks.len) : (k += 1) {
            switch (toks[k].tag) {
                .l_brace => depth += 1,
                .r_brace => {
                    depth -= 1;
                    if (depth == 0) break;
                },
                else => {},
            }
            toks[k].in_test = true;
        }
        if (k < toks.len) toks[k].in_test = true;
        toks[i].in_test = true;
        i = k;
    }
}

pub fn text(source: []const u8, t: Tok) []const u8 {
    return source[t.start..t.end];
}

/// 解出字符串字面量的内容；转义非法时返回 null。
pub fn stringValue(arena: std.mem.Allocator, source: []const u8, t: Tok) ?[]const u8 {
    if (t.tag != .string_literal) return null;
    return std.zig.string_literal.parseAlloc(arena, text(source, t)) catch null;
}

pub const Import = struct {
    spec: []const u8,
    line: u32,
    in_test: bool,
};

pub fn imports(arena: std.mem.Allocator, source: []const u8, toks: []const Tok) ![]Import {
    var out: std.ArrayList(Import) = .empty;
    var i: usize = 0;
    while (i + 3 < toks.len) : (i += 1) {
        const t = toks[i];
        if (t.tag != .builtin or !std.mem.eql(u8, text(source, t), "@import")) continue;
        if (toks[i + 1].tag != .l_paren) continue;
        const spec = stringValue(arena, source, toks[i + 2]) orelse continue;
        try out.append(arena, .{ .spec = spec, .line = t.line, .in_test = t.in_test });
    }
    return out.items;
}

pub const Hit = struct { line: u32 };

/// `findSequenceHits` 的一处命中：所在行与序列首 token 的下标。
pub const SequenceHit = struct { line: u32, token: usize };

/// 查找 `a.b.c` 形式的 token 序列（标识符与 `.` 交替）；test 块内不算。`reads_only`：序列后紧跟 `=`（赋值）的不算。
pub fn findSequenceHits(source: []const u8, toks: []const Tok, sequence: []const u8, reads_only: bool, out: *std.ArrayList(SequenceHit), arena: std.mem.Allocator) !void {
    var parts_buf: [8][]const u8 = undefined;
    var n: usize = 0;
    var it = std.mem.splitScalar(u8, sequence, '.');
    while (it.next()) |p| {
        if (n == parts_buf.len) return error.SequenceTooLong;
        parts_buf[n] = p;
        n += 1;
    }
    const parts = parts_buf[0..n];
    const span = n * 2 - 1;
    var i: usize = 0;
    outer: while (i + span <= toks.len) : (i += 1) {
        if (toks[i].in_test) continue;
        // `x.a.b` 里的 `a.b` 要从 `a` 开始匹配，但 `ab.b` 的后缀不算：首段前面若是标识符的一部分已由分词器分开。
        for (parts, 0..) |p, k| {
            const t = toks[i + k * 2];
            if (t.tag != .identifier or !std.mem.eql(u8, text(source, t), p)) continue :outer;
            if (k + 1 < parts.len and toks[i + k * 2 + 1].tag != .period) continue :outer;
        }
        if (reads_only and i + span < toks.len and toks[i + span].tag == .equal) continue;
        try out.append(arena, .{ .line = toks[i].line, .token = i });
    }
}

/// 下标 `index` 处的 token 所在的函数名（向前找最近的 `fn 名字`；顶层声明里返回 "(top)"）。
pub fn enclosingFunction(source: []const u8, toks: []const Tok, index: usize) []const u8 {
    var i = index;
    var depth: i32 = 0;
    while (i > 0) {
        i -= 1;
        switch (toks[i].tag) {
            .r_brace => depth += 1,
            .l_brace => depth -= 1,
            .keyword_fn => if (depth < 0 and i + 1 < toks.len and toks[i + 1].tag == .identifier) return text(source, toks[i + 1]),
            else => {},
        }
    }
    return "(top)";
}

/// 查找 `a.b.c` 形式的 token 序列（标识符与 `.` 交替）；test 块内不算。
pub fn findSequence(source: []const u8, toks: []const Tok, sequence: []const u8, out_lines: *std.ArrayList(u32), arena: std.mem.Allocator) !void {
    var parts_buf: [8][]const u8 = undefined;
    var n: usize = 0;
    var it = std.mem.splitScalar(u8, sequence, '.');
    while (it.next()) |p| {
        if (n == parts_buf.len) return error.SequenceTooLong;
        parts_buf[n] = p;
        n += 1;
    }
    const parts = parts_buf[0..n];
    const span = n * 2 - 1;
    var i: usize = 0;
    outer: while (i + span <= toks.len) : (i += 1) {
        if (toks[i].in_test) continue;
        for (parts, 0..) |p, k| {
            const t = toks[i + k * 2];
            if (t.tag != .identifier or !std.mem.eql(u8, text(source, t), p)) continue :outer;
            if (k + 1 < parts.len and toks[i + k * 2 + 1].tag != .period) continue :outer;
        }
        try out_lines.append(arena, toks[i].line);
    }
}

pub const TestCount = struct {
    named: usize = 0,
    decl: usize = 0,
    unnamed: usize = 0,

    pub fn total(c: TestCount) usize {
        return c.named + c.decl + c.unnamed;
    }
};

pub fn countTests(toks: []const Tok) TestCount {
    var c: TestCount = .{};
    for (toks, 0..) |t, i| {
        if (t.tag != .keyword_test or i + 1 >= toks.len) continue;
        switch (toks[i + 1].tag) {
            .string_literal => c.named += 1,
            .identifier => c.decl += 1,
            .l_brace => c.unnamed += 1,
            else => {},
        }
    }
    return c;
}

/// 把 `dir/../x.zig` 之类的相对路径归一成以 `/` 分隔、无 `.`/`..` 段的仓库路径。
/// 越过根目录的 `..` 保留在开头（例如 `../vendor/x.zig`）。
pub fn normalize(arena: std.mem.Allocator, base_dir: []const u8, rel: []const u8) ![]const u8 {
    var segs: std.ArrayList([]const u8) = .empty;
    var ups: usize = 0;
    for ([_][]const u8{ base_dir, rel }) |part| {
        var it = std.mem.splitScalar(u8, part, '/');
        while (it.next()) |s| {
            if (s.len == 0 or std.mem.eql(u8, s, ".")) continue;
            if (std.mem.eql(u8, s, "..")) {
                if (segs.items.len > 0) _ = segs.pop() else ups += 1;
                continue;
            }
            try segs.append(arena, s);
        }
    }
    var out: std.ArrayList(u8) = .empty;
    for (0..ups) |_| try out.appendSlice(arena, "../");
    for (segs.items, 0..) |s, k| {
        if (k > 0) try out.append(arena, '/');
        try out.appendSlice(arena, s);
    }
    return out.items;
}

pub fn dirname(path: []const u8) []const u8 {
    const idx = std.mem.lastIndexOfScalar(u8, path, '/') orelse return "";
    return path[0..idx];
}

/// Zig 的规则：以 `.zig` / `.zon` 结尾的是文件，否则是具名模块。
/// `.yix` 里 `@import("styles.yss")` 也是文件。
pub fn isFileImport(spec: []const u8) bool {
    for ([_][]const u8{ ".zig", ".zon", ".yix", ".yss" }) |ext| {
        if (std.mem.endsWith(u8, spec, ext)) return true;
    }
    return false;
}

// ── 测试 ─────────────────────────────────────────────────────────────

const testing = std.testing;

fn importSpecs(arena: std.mem.Allocator, source: [:0]const u8) ![]const []const u8 {
    const toks = try tokenize(arena, source);
    const list = try imports(arena, source, toks);
    var out: std.ArrayList([]const u8) = .empty;
    for (list) |imp| try out.append(arena, imp.spec);
    return out.items;
}

test "normalize relative import paths" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    try testing.expectEqualStrings("src/ui/app_theme.zig", try normalize(a, "src/config", "../ui/app_theme.zig"));
    try testing.expectEqualStrings("src/host/plugin_services.zig", try normalize(a, "src/plugins/bmc_ikvm/protocol", "../../../host/plugin_services.zig"));
    try testing.expectEqualStrings("src/ui/x.zig", try normalize(a, "src/ui", "./x.zig"));
    try testing.expectEqualStrings("src/config/settings_parts/a.zig", try normalize(a, "src/config", "settings_parts/a.zig"));
    try testing.expectEqualStrings("../vendor/x.zig", try normalize(a, "src", "../../vendor/x.zig"));
    try testing.expectEqualStrings("x.zig", try normalize(a, "", "x.zig"));
    try testing.expectEqualStrings("src", dirname("src/main.zig"));
    try testing.expectEqualStrings("", dirname("main.zig"));
    try testing.expect(isFileImport("a.zig") and isFileImport("styles.yss") and !isFileImport("ui") and !isFileImport("std"));
}

test "imports: line numbers, test blocks, multiline and odd spacing" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const src =
        \\const std = @import("std");
        \\// @import("commented.zig") 不算
        \\const s = "@import(\"in_string.zig\")";
        \\const x = @import(
        \\    "multi.zig"
        \\).Thing;
        \\test "t" {
        \\    _ = @import("only_test.zig");
        \\    { _ = @import("nested_test.zig"); }
        \\}
        \\const y = @import ("after.zig");
        \\const z = struct { test { _ = @import("inner_test.zig"); } };
    ;
    const toks = try tokenize(a, src);
    const list = try imports(a, src, toks);
    try testing.expectEqual(@as(usize, 6), list.len);
    try testing.expectEqualStrings("std", list[0].spec);
    try testing.expectEqual(@as(u32, 1), list[0].line);
    try testing.expect(!list[0].in_test);
    try testing.expectEqualStrings("multi.zig", list[1].spec);
    try testing.expectEqual(@as(u32, 4), list[1].line);
    try testing.expectEqualStrings("only_test.zig", list[2].spec);
    try testing.expect(list[2].in_test);
    try testing.expect(list[3].in_test);
    try testing.expectEqualStrings("after.zig", list[4].spec);
    try testing.expect(!list[4].in_test);
    try testing.expectEqual(@as(u32, 11), list[4].line);
    try testing.expectEqualStrings("inner_test.zig", list[5].spec);
    try testing.expect(list[5].in_test);
}

test "identifier sequences skip test blocks" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const src =
        \\const ui = @import("ui");
        \\pub const Vm = struct { node: *ui.Node, count: *ui.Signal(u32) };
        \\fn f(n: anytype) void { n.appendChild(1); }
        \\const T = std.Io.Dir;
        \\const U = std.Io.File;
        \\test "x" { const n: ui.Node = undefined; _ = n; }
    ;
    const toks = try tokenize(a, src);
    var lines: std.ArrayList(u32) = .empty;
    try findSequence(src, toks, "ui.Node", &lines, a);
    try testing.expectEqualSlices(u32, &.{2}, lines.items);
    lines.clearRetainingCapacity();
    try findSequence(src, toks, "ui.Signal", &lines, a);
    try testing.expectEqualSlices(u32, &.{2}, lines.items);
    lines.clearRetainingCapacity();
    try findSequence(src, toks, "appendChild", &lines, a);
    try testing.expectEqualSlices(u32, &.{3}, lines.items);
    lines.clearRetainingCapacity();
    try findSequence(src, toks, "std.Io.Dir", &lines, a);
    try testing.expectEqualSlices(u32, &.{4}, lines.items);
    lines.clearRetainingCapacity();
    try findSequence(src, toks, "ui.box", &lines, a);
    try testing.expectEqual(@as(usize, 0), lines.items.len);
}

test "sequence hits: reads only skips assignments, and the enclosing function is named" {
    const a = std.testing.allocator;
    var arena_state = std.heap.ArenaAllocator.init(a);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const src: [:0]const u8 =
        \\fn name(n: *Node) void { n.meta.ownership.meta.test_id = "x"; }
        \\fn find(n: *Node) bool { return std.mem.eql(u8, n.meta.ownership.meta.test_id orelse "", "x"); }
        \\const Helper = struct {
        \\    fn walk(n: *Node) void { if (n.meta.test_id) |id| _ = id; for (n.children.items) |c| walk(c); }
        \\};
        \\fn check(a: ?u8, b: ?u8) bool { return a == b; }
        \\test "t" { _ = node.meta.test_id; }
    ;
    const toks = try tokenize(arena, src);
    var hits: std.ArrayList(SequenceHit) = .empty;
    try findSequenceHits(src, toks, "meta.test_id", true, &hits, arena);
    try std.testing.expectEqual(@as(usize, 2), hits.items.len);
    try std.testing.expectEqual(@as(u32, 2), hits.items[0].line);
    try std.testing.expectEqualStrings("find", enclosingFunction(src, toks, hits.items[0].token));
    try std.testing.expectEqual(@as(u32, 4), hits.items[1].line);
    try std.testing.expectEqualStrings("walk", enclosingFunction(src, toks, hits.items[1].token));
    hits.clearRetainingCapacity();
    try findSequenceHits(src, toks, "meta.test_id", false, &hits, arena);
    try std.testing.expectEqual(@as(usize, 3), hits.items.len);
}

test "count tests by kind" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const src =
        \\test "a" {}
        \\test "b" { }
        \\test decl {}
        \\test { _ = @import("x.zig"); }
        \\const s = "test \"not a test\" {}";
        \\// test "comment" {}
    ;
    const toks = try tokenize(arena_state.allocator(), src);
    const c = countTests(toks);
    try testing.expectEqual(@as(usize, 2), c.named);
    try testing.expectEqual(@as(usize, 1), c.decl);
    try testing.expectEqual(@as(usize, 1), c.unnamed);
}

// V-9：`.yix` 文件能否用 Zig 分词器提取 @import。样本取自 vendor/zenit 自带的 .yix。

test "V-9: yix sample — examples/yix_counter/counter.yix" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const src =
        \\const ui = @import("ui");
        \\const Button = ui.widgets.Button;
        \\/// Styles in styles.yss
        \\const S = @import("styles.yss");
        \\
        \\pub fn Counter(start: u32 = 0) View {
        \\    var count: u32 = signal(start);
        \\    const doubled = computed(count * 2);
        \\    const even = computed(count % 2 == 0);
        \\    return (
        \\        <col style={S.root}>
        \\            <text style={S.title}>Reactive Counter</text>
        \\            <text style={S.counter_text}>count = {count}</text>
        \\            <row style={S.Badge.of(.{ .even = even })}>
        \\                {if (even) <text style={S.badge_text}>even</text> else <text style={S.badge_text}>odd</text>}
        \\            </row>
        \\            <row style={S.button_row}>
        \\                <Button variant={.primary} onClick={count += 1}>+1</Button>
        \\                <Button variant={.secondary} onClick={count = 0}>Reset</Button>
        \\            </row>
        \\        </col>
        \\    );
        \\}
    ;
    const specs = try importSpecs(arena_state.allocator(), src);
    try testing.expectEqual(@as(usize, 2), specs.len);
    try testing.expectEqualStrings("ui", specs[0]);
    try testing.expectEqualStrings("styles.yss", specs[1]);
}

test "V-9: yix sample — zenit src/ui/components/alert/alert.yix header (verbatim) + adversarial template text" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const src =
        \\//! Alert view. Styles in styles.yss, shared types and tests in mod.zig.
        \\const ui = @import("../../ui.zig");
        \\const mod = @import("mod.zig");
        \\const S = @import("styles.yss");
        \\const AlertVariant = mod.AlertVariant;
        \\
        \\const icons = @import("zenit_icons");
        \\pub fn Alert(props: mod.Props) View {
        \\    return (
        \\        <row style={S.root} testId={props.test_id} role="alert">
        \\            <text>Don't panic — it's "fine"</text>
        \\            <text>https://example.com/path // not a comment</text>
        \\            {if (props.closable) <Button onClick={props.on_close}>×</Button>}
        \\        </row>
        \\    );
        \\}
        \\const late = @import("late.zig");
    ;
    const specs = try importSpecs(arena_state.allocator(), src);
    try testing.expectEqual(@as(usize, 5), specs.len);
    try testing.expectEqualStrings("../../ui.zig", specs[0]);
    try testing.expectEqualStrings("mod.zig", specs[1]);
    try testing.expectEqualStrings("styles.yss", specs[2]);
    try testing.expectEqualStrings("zenit_icons", specs[3]);
    // 模板文本里的撇号、引号、`//` 只会让分词器在当行产生 invalid token 或注释，下一行恢复。
    try testing.expectEqualStrings("late.zig", specs[4]);
}

test "V-9: yix sample — tests/yix/review_reactive.yix (one-line components)" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const src =
        \\const ui = @import("ui");
        \\pub var store: ?*ui.Signal(i32) = null;
        \\fn readStore() i32 { return store.?.get(); }
        \\pub fn ExternalOnly() View { return <text>{readStore()}</text>; }
        \\pub fn ExternalVisible() View { return <box visible={readStore() > 0} />; }
        \\fn NullReceiver(args: anytype) @TypeOf(ui.view.text(.{}, "nil")) {
        \\    return ui.view.text(.{}, if (args.value == null) "nil" else "set");
        \\}
        \\pub fn ComptimeStructCall() View { return <TypeReceiver config={@import("cfg.zig").typeConfig()} />; }
    ;
    const specs = try importSpecs(arena_state.allocator(), src);
    try testing.expectEqual(@as(usize, 2), specs.len);
    try testing.expectEqualStrings("cfg.zig", specs[1]);
}
