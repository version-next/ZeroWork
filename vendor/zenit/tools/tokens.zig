//! Host CLI for application-owned Design System tokens.
const std = @import("std");
const resolver = @import("token_resolver");
const emitter = @import("token_emitter");
const model = @import("token_model");

pub fn main(init: std.process.Init) void {
    run(init) catch |err| {
        std.debug.print("zenit-tokens: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
}
fn usage() noreturn {
    std.debug.print(
        \\usage: zenit-tokens check BASE.json [OVERLAY.json ...]
        \\       zenit-tokens generate BASE.json [OVERLAY.json ...] --out OUTPUT.zig
        \\       zenit-tokens explain BASE.json [OVERLAY.json ...] TOKEN_PATH --mode MODE
        \\Overlays merge in order; replacing a lower layer's token needs {{"$override": true, "$value": ...}}.
        \\
    , .{});
    std.process.exit(64);
}
fn run(init: std.process.Init) !void {
    const io = init.io;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    if (args.len < 3) usage();
    const check = std.mem.eql(u8, args[1], "check");
    const generate = std.mem.eql(u8, args[1], "generate");
    const explain = std.mem.eql(u8, args[1], "explain");
    // Input files: everything between the command and the trailing options.
    var inputs: []const []const u8 = undefined;
    if (check) {
        inputs = args[2..];
    } else if (generate) {
        if (args.len < 5 or !std.mem.eql(u8, args[args.len - 2], "--out")) usage();
        inputs = args[2 .. args.len - 2];
    } else if (explain) {
        if (args.len < 6 or !std.mem.eql(u8, args[args.len - 2], "--mode")) usage();
        inputs = args[2 .. args.len - 3];
    } else usage();
    for (inputs) |input| if (std.mem.startsWith(u8, input, "--")) usage();
    const layers = try a.alloc(model.Layer, inputs.len);
    for (inputs, layers) |path, *layer| layer.* = .{
        .name = path,
        .source = try std.Io.Dir.cwd().readFileAlloc(io, path, a, .limited(8 * 1024 * 1024)),
    };
    var doc = try resolver.parseLayers(a, layers);
    defer doc.deinit();
    if (doc.diagnostic) |d| {
        const layer = layers[d.layer];
        var line: usize = 1;
        var column: usize = 1;
        for (layer.source[0..@min(d.offset, layer.source.len)]) |c| {
            if (c == '\n') {
                line += 1;
                column = 1;
            } else column += 1;
        }
        std.debug.print("{s}:{d}:{d}: {s}: {s}\n", .{ layer.name, line, column, d.pointer, d.message });
        std.process.exit(1);
    }
    if (check) {
        std.debug.print("valid: {d} tokens, {d} modes, {d} layers\n", .{ doc.tokens.len, doc.modes.len, layers.len });
    } else if (generate) {
        const output = try emitter.generate(a, &doc);
        var buffer: [4096]u8 = undefined;
        var atomic = try std.Io.Dir.cwd().createFileAtomic(io, args[args.len - 1], .{ .replace = true });
        defer atomic.deinit(io);
        var writer = atomic.file.writer(io, &buffer);
        try writer.interface.writeAll(output);
        try writer.interface.flush();
        try atomic.replace(io);
    } else {
        const mode_name = args[args.len - 1];
        const token_path = args[args.len - 3];
        const mi = for (doc.modes, 0..) |mode, i| {
            if (std.mem.eql(u8, mode.name, mode_name)) break i;
        } else return error.UnknownMode;
        const ti = for (doc.tokens, 0..) |tok, i| {
            if (std.mem.eql(u8, tok.path, token_path) or std.mem.eql(u8, tok.source_path, token_path)) break i;
        } else return error.UnknownToken;
        const tok = doc.tokens[ti];
        if (layers.len > 1) {
            std.debug.print("{s} [{s}]\n  source: {s} {s}#{s}\n  value: {any}\n", .{ tok.path, doc.modes[mi].name, tok.source_path, layers[tok.layer].name, tok.pointer, doc.modes[mi].values[ti] });
        } else {
            std.debug.print("{s} [{s}]\n  source: {s} {s}\n  value: {any}\n", .{ tok.path, doc.modes[mi].name, tok.source_path, tok.pointer, doc.modes[mi].values[ti] });
        }
        try trace(a, &doc, mi, ti);
    }
}

fn trace(a: std.mem.Allocator, doc: *const model.Document, mi: usize, ti: usize) !void {
    // One parsed tree per layer; a token's expression lives in the layer that last declared it.
    const trees = try a.alloc(std.json.Value, doc.layers.len);
    for (doc.layers, trees) |layer, *tree| tree.* = (try std.json.parseFromSlice(std.json.Value, a, layer.source, .{})).value;
    var pending: std.ArrayList(usize) = .empty;
    defer pending.deinit(a);
    var seen = std.AutoHashMap(usize, void).init(a);
    defer seen.deinit();
    try pending.append(a, ti);
    var cursor: usize = 0;
    while (cursor < pending.items.len) : (cursor += 1) {
        const idx = pending.items[cursor];
        if ((try seen.getOrPut(idx)).found_existing) continue;
        var expression = trees[doc.tokens[idx].layer];
        var parts = std.mem.splitScalar(u8, doc.tokens[idx].source_path, '.');
        const found = while (parts.next()) |part| {
            expression = (if (expression == .object) expression.object.get(part) else null) orelse break false;
        } else true;
        if (!found) {
            // Component role the theme omitted: the resolver aliased it to its default target.
            for (resolver.roles.component_roles) |role| if (std.mem.eql(u8, role.path, doc.tokens[idx].path)) {
                std.debug.print("  default role: {s} -> {s}\n", .{ doc.tokens[idx].source_path, role.target });
                for (doc.tokens, 0..) |t, j| if (std.mem.eql(u8, t.path, role.target)) try pending.append(a, j);
            };
            continue;
        }
        if (expression == .object) if (expression.object.get("$value")) |v| {
            expression = v;
        };
        if (expression == .object and expression.object.contains("$light")) {
            var selected = mi;
            while (true) {
                const key = try std.fmt.allocPrint(a, "${s}", .{doc.modes[selected].name});
                if (expression.object.get(key)) |v| {
                    std.debug.print("  branch: {s} -> {s} (references still resolve in {s})\n", .{ doc.tokens[idx].source_path, key, doc.modes[mi].name });
                    expression = v;
                    break;
                }
                selected = doc.modes[selected].fallback.?;
            }
        }
        try refs(a, doc, idx, expression, &pending);
    }
}
fn refs(a: std.mem.Allocator, doc: *const model.Document, from: usize, v: std.json.Value, pending: *std.ArrayList(usize)) anyerror!void {
    if (v == .string and std.mem.startsWith(u8, v.string, "{")) {
        const path = v.string[1 .. v.string.len - 1];
        for (doc.tokens, 0..) |tok, idx| if (std.mem.eql(u8, tok.source_path, path)) {
            std.debug.print("  reference: {s} -> {s}\n", .{ doc.tokens[from].source_path, path });
            try pending.append(a, idx);
            return;
        };
    } else if (v == .object) {
        var it = v.object.iterator();
        while (it.next()) |entry| try refs(a, doc, from, entry.value_ptr.*, pending);
    }
}
