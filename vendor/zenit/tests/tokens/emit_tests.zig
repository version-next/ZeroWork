const std = @import("std");
const m = @import("token_model");
const emit = @import("token_emitter");

test "empty provider output parses and includes fixed category types" {
    var doc: m.Document = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator), .modes = &.{.{ .name = "light", .scheme = .light, .fallback = null, .values = &.{} }} };
    defer doc.deinit();
    const output = try emit.generate(std.testing.allocator, &doc);
    defer std.testing.allocator.free(output);
    const z = try std.testing.allocator.dupeSentinel(u8, output, 0);
    defer std.testing.allocator.free(z);
    var ast = try std.zig.Ast.parse(std.testing.allocator, z, .{});
    defer ast.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), ast.errors.len);
    try std.testing.expect(std.mem.indexOf(u8, output, "pub const refs = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "_ = t;") != null);
}
test "invalid documents cannot generate" {
    var doc: m.Document = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator), .diagnostic = .{ .offset = 0, .pointer = "", .message = "invalid" } };
    defer doc.deinit();
    try std.testing.expectError(error.InvalidDocument, emit.generate(std.testing.allocator, &doc));
}

test "layered documents name the declaring file in metadata pointers; single files stay bare" {
    const resolver = @import("token_resolver");
    var single = try resolver.parse(std.testing.allocator, "{\"$version\":1,\"tokens\":{\"color\":{\"a\":\"#000\"}}}");
    defer single.deinit();
    const one = try emit.generate(std.testing.allocator, &single);
    defer std.testing.allocator.free(one);
    try std.testing.expect(std.mem.indexOf(u8, one, ".pointer = \"/tokens/color/a\"") != null);
    var doc = try resolver.parseLayers(std.testing.allocator, &.{
        .{ .name = "base.json", .source = "{\"$version\":1,\"tokens\":{\"color\":{\"a\":\"#000\"}}}" },
        .{ .name = "src/app.tokens.json", .source = "{\"$version\":1,\"semantic\":{\"color\":{\"b\":\"{tokens.color.a}\"}}}" },
    });
    defer doc.deinit();
    const two = try emit.generate(std.testing.allocator, &doc);
    defer std.testing.allocator.free(two);
    try std.testing.expect(std.mem.indexOf(u8, two, ".pointer = \"base.json#/tokens/color/a\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, two, ".pointer = \"src/app.tokens.json#/semantic/color/b\"") != null);
}
