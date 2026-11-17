//! Web DOM host demo: the counter_reactive UI plus a scrolling list and a text
//! input, unchanged zenit code running in the browser via ui.web.
const std = @import("std");
const ui = @import("ui");
const v = ui.view;
const W = ui.widgets;
const S = @import("styles.zig");

pub const panic = ui.web.panic;
pub const std_options_debug_io = ui.web.io;
/// No glass here: build without the WebGPU glass tier (docs/WEB_GLASS_DESIGN.md §7).
pub const zenit_web_glass = false;
comptime {
    ui.web.exportApp(@This());
}

// Persistence demo: plain desktop std.Io.Dir code; in the browser `ui.web.io`
// is an in-memory filesystem mirrored to IndexedDB by the JS runtime.
const count_path = "/demo/count.txt";
const visits_path = "/demo/visits.txt";

fn readNumber(path: []const u8) u32 {
    var buf: [32]u8 = undefined;
    const text = std.Io.Dir.cwd().readFile(ui.web.io, path, &buf) catch return 0;
    return std.fmt.parseInt(u32, std.mem.trim(u8, text, " \n"), 10) catch 0;
}

fn writeNumber(path: []const u8, n: u32) void {
    var buf: [16]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{d}", .{n}) catch return;
    const cwd = std.Io.Dir.cwd();
    cwd.createDirPath(ui.web.io, "/demo") catch {};
    cwd.writeFile(ui.web.io, .{ .sub_path = path, .data = text }) catch |err| {
        var msg: [64]u8 = undefined;
        ui.web.consoleLog(std.fmt.bufPrint(&msg, "writeFile failed: {s}", .{@errorName(err)}) catch "writeFile failed");
    };
}

fn inc(n: u32) u32 {
    writeNumber(count_path, n + 1);
    return n + 1;
}
fn isEven(n: u32) bool {
    return n % 2 == 0;
}

const Row = struct { id: u32, label: []const u8 };
const row_ids = blk: {
    @setEvalBranchQuota(400_000);
    var out: [200]Row = undefined;
    for (&out, 0..) |*r, i| r.* = .{ .id = i, .label = std.fmt.comptimePrint("Row {d}: zenit node mirrored into the DOM", .{i}) };
    break :blk out;
};

const row_props = .{ .style = S.derivedText };
fn rowView(r: Row) @TypeOf(v.text(row_props, @as([]const u8, ""))) {
    return v.text(row_props, r.label);
}

/// A board-like surface painted by the WebGPU canvas island (not DOM): shapes,
/// borders, shadows, gradients, text and icons from zenit's own display list.
fn islandView(cx: *ui.Cx) !*ui.Node {
    const board = try ui.box(cx, .{ .width = .{ .px = 420 }, .height = .{ .px = 200 }, .background = ui.Color.hex(0xF7F6F2), .overflow_hidden = true, .position = .relative }, .{});
    board.style.ensureExtPanic(cx.allocator).corner_radius = .{ .all = 14 };
    const Shape = struct { x: f32, y: f32, w: f32, h: f32, color: u24, r: f32, border: f32 = 0, ellipse: bool = false, shadow: bool = false, grad: bool = false };
    const shapes = [_]Shape{
        .{ .x = 20, .y = 20, .w = 110, .h = 80, .color = 0xFFE27A, .r = 6, .shadow = true },
        .{ .x = 150, .y = 30, .w = 90, .h = 90, .color = 0x87D7FF, .r = 0, .ellipse = true, .border = 3 },
        .{ .x = 260, .y = 20, .w = 140, .h = 70, .color = 0xD7B8FF, .r = 18, .grad = true },
        .{ .x = 260, .y = 110, .w = 140, .h = 70, .color = 0xFFFFFF, .r = 10, .border = 2, .shadow = true },
    };
    for (shapes) |sh| {
        const b = try ui.box(cx, .{ .position = .absolute, .width = .{ .px = sh.w }, .height = .{ .px = sh.h }, .background = ui.Color.hex(sh.color) }, .{});
        b.setStyle(null, .translate_x, sh.x);
        b.setStyle(null, .translate_y, sh.y);
        const ext = b.style.ensureExtPanic(cx.allocator);
        ext.corner_radius = .{ .all = sh.r };
        if (sh.ellipse) ext.shape = .ellipse;
        if (sh.border > 0) {
            b.style.border.width = sh.border;
            b.style.border.color = ui.Color.hex(0x2F5BFF);
        }
        if (sh.shadow) ext.setShadow(.{ .color = ui.Color.rgba(0, 0, 0, 60), .blur = 14, .offset_y = 6 });
        if (sh.grad) ext.gradient = .{ .from = ui.Color.hex(0xD7B8FF), .to = ui.Color.hex(0x2F5BFF), .direction = .horizontal };
        try board.appendChild(cx.allocator, b);
    }
    const label = try ui.text(cx, "WebGPU island · 画板", .{ .font_size = 15, .font_weight = 600, .color = ui.Color.hex(0x1F1F1F) });
    label.setStyle(null, .translate_x, 28);
    label.setStyle(null, .translate_y, 150);
    label.style.position = .absolute;
    try board.appendChild(cx.allocator, label);
    const star = try ui.iconTint(cx, ui.icons.chevron_down, ui.Color.hex(0xE0453B), .{ .position = .absolute, .width = .{ .px = 28 }, .height = .{ .px = 28 } });
    star.setStyle(null, .translate_x, 200);
    star.setStyle(null, .translate_y, 140);
    try board.appendChild(cx.allocator, star);
    ui.web.setCanvasIsland(board);
    return board;
}

pub fn mount(cx: *ui.Cx, scope: *ui.Scope) anyerror!*ui.Node {
    const count = try scope.createSignal(u32, readNumber(count_path));
    const visits = readNumber(visits_path) + 1;
    writeNumber(visits_path, visits);
    const doubled = try scope.createMemo(u32, .{ .count = count }, struct {
        fn compute(ctx: anytype) u32 {
            return ctx.count.get() * 2;
        }
    }.compute);
    const even = ui.map(count, isEven);
    const typed = try scope.createText("", .{});

    const root = try v.render(scope, cx, v.col(.{ .style = S.root }, .{
        v.text(.{ .style = S.title }, "Reactive Counter · Web DOM host"),
        v.text(.{ .style = S.counterText }, v.fmt("count = {d}", .{count})),
        v.text(.{ .style = S.derivedText }, v.fmt("doubled = {d}", .{doubled})),
        v.text(.{ .style = S.derivedText }, v.fmt("visits = {d}", .{visits})),
        v.row(.{ .style = S.Badge.of(.{ .even = even }) }, .{
            v.show(even, .{v.text(.{ .style = S.badgeText }, "even")})
                .fallback(.{v.text(.{ .style = S.badgeText }, "odd")}),
        }),
        W.Input(.{ .placeholder = "输入中文试试 / type here", .value = typed }),
        v.text(.{ .style = S.derivedText }, v.fmt("typed: {s}", .{typed})),
        v.row(.{ .style = S.buttonRow, .test_id = "buttons" }, .{
            W.Button(.{ .label = "+1", .variant = .primary, .on_click = ui.on.update(count, inc) }),
            W.Button(.{ .label = "Reset", .variant = .secondary, .on_click = ui.on.set(count, 0) }),
        }),
        v.with(W.ScrollArea(.{ .direction = .vertical, .height = 160, .width = 420 }), .{v.col(.{}, .{v.each(&row_ids, .id, rowView)})}),
    }));
    try root.appendChild(cx.allocator, try islandView(cx));
    return root;
}
