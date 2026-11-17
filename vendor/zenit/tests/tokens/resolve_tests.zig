const std = @import("std");
const resolver = @import("token_resolver");
const m = @import("token_model");
const a = std.testing.allocator;

fn value(doc: *const m.Document, mode: []const u8, path: []const u8) !m.Value {
    for (doc.modes) |mde| if (std.mem.eql(u8, mde.name, mode)) {
        for (doc.tokens, 0..) |tok, i| if (std.mem.eql(u8, tok.path, path)) return mde.values[i];
    };
    return error.NotFound;
}

const valid =
    \\{"$version":1,"$modes":{"hc":{"scheme":"dark","fallback":"dark"}},
    \\"tokens":{"font_size":{"xLargeBlaBla":32},"color":{"base":{"$light":"#1234","$dark":"#11223344","$hc":"#ff0"}}},
    \\"semantic":{"color":{"surface":{"$light":"{tokens.color.base}"},"alias":"{semantic.color.surface}"},
    \\"typography":{"title":{"font_size":"{tokens.font_size.xLargeBlaBla}"}},
    \\"shadow":{"card":{"color":"{semantic.color.surface}"}}}}
;

test "aliases preserve request mode through fallback; compound defaults are explicit" {
    var doc = try resolver.parse(a, valid);
    defer doc.deinit();
    if (doc.diagnostic) |d| std.debug.print("{s} {s}\n", .{ d.pointer, d.message });
    try std.testing.expect(doc.diagnostic == null);
    try std.testing.expectEqual(@as(u8, 0x44), (try value(&doc, "light", "color.alias")).color.a);
    try std.testing.expectEqual(@as(u8, 255), (try value(&doc, "hc", "color.alias")).color.r);
    try std.testing.expectEqual(@as(u8, 0), (try value(&doc, "hc", "color.alias")).color.b);
    const shadow = (try value(&doc, "dark", "shadow.card")).shadow;
    try std.testing.expectEqual(@as(f32, 0), shadow.blur);
    try std.testing.expectEqual(@as(f32, 0), shadow.offset_y);
    const typo = (try value(&doc, "dark", "typography.title")).typography;
    try std.testing.expectEqual(@as(?f32, 32), typo.font_size);
    try std.testing.expect(typo.font_weight == null and typo.line_height == null);
}

test "mode-specific reference graphs must not be rejected as a union cycle" {
    const source =
        \\{"$version":1,"tokens":{"space":{"a":{"$light":"{tokens.space.b}","$dark":2},"b":{"$light":1,"$dark":"{tokens.space.a}"}}}}
    ;
    var doc = try resolver.parse(a, source);
    defer doc.deinit();
    try std.testing.expect(doc.diagnostic == null);
    try std.testing.expectEqual(@as(f32, 1), (try value(&doc, "light", "space.a")).number);
    try std.testing.expectEqual(@as(f32, 2), (try value(&doc, "dark", "space.b")).number);
}

test "reject invalid declarations before emitting any provider" {
    const bodies = [_][]const u8{
        \\{"$version":1,"tokens":{"space":{"x":1}},"semantic":{"space":{"x":1}}}
        ,
        \\{"$version":1,"tokens":{"color":{"action":"#fff"}},"semantic":{"color":{"action":{"hover":"#000"}}}}
        ,
        \\{"$version":1,"tokens":{"space":{"x":1,"\u0078":2}}}
        ,
        \\{"$version":1,"tokens":{"space":{"x":"{semantic.space.y}"}},"semantic":{"space":{"y":2}}}
        ,
        \\{"$version":1,"tokens":{"space":{"x":"{tokens.duration.x}"},"duration":{"x":1}}}
        ,
        \\{"$version":1,"tokens":{"space":{"x":"{tokens.space.missing}"}}}
        ,
        \\{"$version":1,"tokens":{"space":{"x":"{tokens.space.y}","y":"{tokens.space.x}"}}}
        ,
        \\{"$version":1,"tokens":{"space":{"x":{"$dark":2}}}}
        ,
        \\{"$version":1,"tokens":{"space":{"x":{"$light":1,"$dakr":2}}}}
        ,
        \\{"$version":1,"tokens":{"font_size":{"x":1e-100}}}
        ,
        \\{"$version":1,"tokens":{"space":{"x":1e100}}}
        ,
        \\{"$version":1,"tokens":{"font_weight":{"x":400.5}}}
        ,
        \\{"$version":1,"tokens":{"opacity":{"x":1.1}}}
        ,
        \\{"$version":1,"tokens":{"color":{"x":"#12345"}}}
        ,
        \\{"$version":1,"tokens":{"shadow":{"x":{"color":"#000","blur":-1}}}}
        ,
        \\{"$version":1,"tokens":{"typography":{"x":{}}}}
        ,
        \\{"$version":1,"tokens":{"typography":{"x":{"font_size":{"$light":14}}}}}
        ,
        \\{"$version":1,"tokens":{"control":{"x":{"font_size":10,"line_height":1,"radius":0,"padding_y":0,"padding_h":0,"padding_leading_icon":0,"icon_size":20,"gap":0}}}}
        ,
        \\{"$version":1,"tokens":{"space":{"x":{"$value":1,"oops":2}}}}
        ,
        \\{"$version":1,"tokens":{},"unexpected":{}}
        ,
        \\{"$version":1,"tokens":{},"$modes":{"hc":{"scheme":"dark","fallback":"hc"}}}
        ,
        \\{"$version":1,"tokens":{"color":{"x":"#000"}},"bindings":{"color.typo":"{tokens.color.x}"}}
        ,
        \\{"$version":1,"tokens":{"space":{"x":1}},"bindings":{"color.bg_primary":"{tokens.space.x}"}}
        ,
        \\{"$version":1,"tokens":{},}
        ,
        \\{"$version":1,"tokens":{"space":{"x":true}}}
        ,
        \\{"$version":1,"tokens":{"space":{"x":null}}}
        ,
        \\{"$version":1,"tokens":{"space":{"x":[1,2]}}}
        ,
    };
    for (bodies) |source| {
        var doc = try resolver.parse(a, source);
        defer doc.deinit();
        if (doc.diagnostic == null) std.debug.print("unexpected success: {s}\n", .{source});
        try std.testing.expect(doc.diagnostic != null);
        try std.testing.expect(doc.diagnostic.?.offset <= source.len);
        try std.testing.expect(doc.diagnostic.?.message.len > 0);
    }
}

test "empty categories, nested merged groups, metadata and arbitrary names" {
    const source =
        \\{"$version":1,"tokens":{"color":{},"space":{"group":{"500":1,"error":2,"extra-large":3}},"font_size":{"same":14}},"semantic":{"space":{"group":{"new":{"$value":4,"$description":"note"}},"same":5}}}
    ;
    var doc = try resolver.parse(a, source);
    defer doc.deinit();
    try std.testing.expect(doc.diagnostic == null);
    try std.testing.expectEqual(@as(usize, 6), doc.tokens.len);
    try std.testing.expectEqual(@as(f32, 4), (try value(&doc, "dark", "space.group.new")).number);
}

fn allocationProbe(allocator: std.mem.Allocator) !void {
    var doc = try resolver.parse(allocator, valid);
    defer doc.deinit();
    try std.testing.expect(doc.diagnostic == null);
    var bad = try resolver.parse(allocator, "{\"$version\":1,\"tokens\":{\"space\":{\"x\":-1}}}");
    defer bad.deinit();
    try std.testing.expect(bad.diagnostic != null);
}
test "resolver owns all allocations on success error and allocation failure" {
    try std.testing.checkAllAllocationFailures(a, allocationProbe, .{});
}

test "generation is byte-stable across declaration order and retains precise locations" {
    const emitter = @import("token_emitter");
    const left = "{\"$version\":1,\"tokens\":{\"space\":{\"b\":2,\"a\":1}}}";
    const right = "{\"tokens\":{\"space\":{\"a\":1,\"b\":2}},\"$version\":1}";
    var d1 = try resolver.parse(a, left);
    defer d1.deinit();
    var d2 = try resolver.parse(a, right);
    defer d2.deinit();
    try std.testing.expect(d1.diagnostic == null and d2.diagnostic == null);
    const out1 = try emitter.generate(a, &d1);
    defer a.free(out1);
    const out2 = try emitter.generate(a, &d2);
    defer a.free(out2);
    try std.testing.expectEqualStrings(out1, out2);
    const malformed = "{\n \"$version\":1,\n \"tokens\":{\"space\":{\"ok\":1,\"bad\":-2}}}";
    var bad = try resolver.parse(a, malformed);
    defer bad.deinit();
    try std.testing.expect(bad.diagnostic != null);
    try std.testing.expectEqualStrings("/tokens/space/bad", bad.diagnostic.?.pointer);
    try std.testing.expect(bad.diagnostic.?.offset >= std.mem.indexOf(u8, malformed, "\"bad\"").?);
}

fn emissionAllocationProbe(allocator: std.mem.Allocator, doc: *const m.Document) !void {
    const output = try @import("token_emitter").generate(allocator, doc);
    defer allocator.free(output);
}
test "emitter releases transient allocations and returned output on OOM" {
    var doc = try resolver.parse(a, valid);
    defer doc.deinit();
    try std.testing.expect(doc.diagnostic == null);
    try std.testing.checkAllAllocationFailures(a, emissionAllocationProbe, .{&doc});
}

test "deep dependency chains use a bounded traversal rather than JSON recursion depth" {
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(a);
    try source.appendSlice(a, "{\"$version\":1,\"tokens\":{\"space\":{");
    for (0..1024) |i| {
        const part = try std.fmt.allocPrint(a, "\"n{d}\":\"{{tokens.space.n{d}}}\",", .{ i, i + 1 });
        defer a.free(part);
        try source.appendSlice(a, part);
    }
    try source.appendSlice(a, "\"n1024\":7}}}");
    var doc = try resolver.parse(a, source.items);
    defer doc.deinit();
    try std.testing.expect(doc.diagnostic == null);
    try std.testing.expectEqual(@as(f32, 7), (try value(&doc, "dark", "space.n0")).number);
}

test "JSON depth and malformed UTF-8 fail safely" {
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(a);
    try source.appendSlice(a, "{\"$version\":1,\"tokens\":{\"space\":{");
    for (0..65) |_| try source.appendSlice(a, "\"g\":{");
    try source.appendSlice(a, "\"x\":1");
    for (0..68) |_| try source.append(a, '}');
    var doc = try resolver.parse(a, source.items);
    defer doc.deinit();
    try std.testing.expect(doc.diagnostic != null);
    var utf = try resolver.parse(a, "{\"$version\":1,\"tokens\":{},\"$schema\":\"\xff\"}");
    defer utf.deinit();
    try std.testing.expect(utf.diagnostic != null);
}

test "hex syntax excludes signed or underscored integer spellings" {
    for ([_][]const u8{ "#+1+1+1", "#0_0_0_" }) |color| {
        const source = try std.fmt.allocPrint(a, "{{\"$version\":1,\"tokens\":{{\"color\":{{\"x\":\"{s}\"}}}}}}", .{color});
        defer a.free(source);
        var doc = try resolver.parse(a, source);
        defer doc.deinit();
        try std.testing.expect(doc.diagnostic != null);
    }
}

test "bindings is not part of the token language" {
    var doc = try resolver.parse(a, "{\"$version\":1,\"tokens\":{},\"bindings\":{}}");
    defer doc.deinit();
    const diagnostic = doc.diagnostic orelse return error.ExpectedDiagnostic;
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.message, "bindings") != null);
}

test "component size matrices are not a theme category" {
    var doc = try resolver.parse(a,
        \\{"$version":1,"tokens":{"control":{"md":{"font_size":14,"line_height":1.25,"radius":8,"padding_y":7.25,"padding_h":12,"padding_leading_icon":10,"icon_size":16,"gap":6}}}}
    );
    defer doc.deinit();
    const diagnostic = doc.diagnostic orelse return error.ExpectedDiagnostic;
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.message, "control") != null);
}

fn colorOf(doc: *const m.Document, mode: []const u8, path: []const u8) !u32 {
    const c = (try value(doc, mode, path)).color;
    return @as(u32, c.r) << 24 | @as(u32, c.g) << 16 | @as(u32, c.b) << 8 | c.a;
}

test "component roles a theme omits become aliases of their default target" {
    const source =
        \\{"$version":1,"tokens":{"color":{"blue":"#0000ff","red":"#ff0000"}},
        \\"semantic":{"color":{"accent":{"$light":"{tokens.color.blue}","$dark":"#000080"},"fg_inverse":"#ffffff",
        \\"danger":"{tokens.color.red}","checkbox-fg":"#123456","switch_track_on":"#abcdef"}}}
    ;
    var doc = try resolver.parse(a, source);
    defer doc.deinit();
    if (doc.diagnostic) |d| std.debug.print("{s} {s}\n", .{ d.pointer, d.message });
    try std.testing.expect(doc.diagnostic == null);
    // Filled per mode from the target.
    try std.testing.expectEqual(@as(u32, 0x0000ffff), try colorOf(&doc, "light", "color.progress_fill"));
    try std.testing.expectEqual(@as(u32, 0x000080ff), try colorOf(&doc, "dark", "color.progress_fill"));
    try std.testing.expectEqual(@as(u32, 0x0000ffff), try colorOf(&doc, "light", "color.checkbox_checked_bg"));
    try std.testing.expectEqual(@as(u32, 0xff0000ff), try colorOf(&doc, "dark", "color.button_danger_bg"));
    try std.testing.expectEqual(@as(u32, 0xffffffff), try colorOf(&doc, "light", "color.switch_thumb_on"));
    // Declared roles win, in either spelling; no second spelling is added.
    try std.testing.expectEqual(@as(u32, 0xabcdefff), try colorOf(&doc, "light", "color.switch_track_on"));
    try std.testing.expectEqual(@as(u32, 0x123456ff), try colorOf(&doc, "light", "color.checkbox-fg"));
    try std.testing.expectError(error.NotFound, value(&doc, "light", "color.checkbox_fg"));
    // Roles whose target the theme lacks are not invented.
    try std.testing.expectError(error.NotFound, value(&doc, "light", "color.range_track"));
    try std.testing.expectError(error.NotFound, value(&doc, "light", "color.bg_focus"));
    // Filled roles are semantic aliases with a stable source identity.
    for (doc.tokens) |tok| if (std.mem.eql(u8, tok.path, "color.progress_fill")) {
        try std.testing.expectEqualStrings("semantic.color.progress_fill", tok.source_path);
        try std.testing.expectEqualStrings("/semantic/color/progress_fill", tok.pointer);
    };
}

test "a theme without any role target gains no tokens" {
    var doc = try resolver.parse(a, "{\"$version\":1,\"tokens\":{\"color\":{\"ink\":\"#000\"}}}");
    defer doc.deinit();
    try std.testing.expect(doc.diagnostic == null);
    try std.testing.expectEqual(@as(usize, 1), doc.tokens.len);
}

// ---- Application theme layers ------------------------------------------------------------

const base_layer =
    \\{"$version":1,"$modes":{"hc":{"scheme":"dark","fallback":"dark"}},
    \\"tokens":{"color":{"blue":{"500":"#0000ffff"}}},
    \\"semantic":{"color":{"accent":{"$light":"{tokens.color.blue.500}","$dark":"#000080ff"},"link":"{semantic.color.accent}"}}}
;

fn layered(overlays: []const []const u8) !m.Document {
    var layers: [4]resolver.Layer = undefined;
    layers[0] = .{ .name = "base.json", .source = base_layer };
    for (overlays, 1..) |src, i| layers[i] = .{ .name = if (i == 1) "app.json" else "app2.json", .source = src };
    return resolver.parseLayers(a, layers[0 .. overlays.len + 1]);
}

fn expectDiagnostic(doc: *const m.Document, layer: usize, pointer: []const u8, needle: []const u8) !void {
    const d = doc.diagnostic orelse return error.ExpectedDiagnostic;
    if (std.mem.indexOf(u8, d.message, needle) == null) {
        std.debug.print("diagnostic: {s} {s}\n", .{ d.pointer, d.message });
        return error.WrongDiagnostic;
    }
    try std.testing.expectEqual(layer, d.layer);
    try std.testing.expectEqualStrings(pointer, d.pointer);
    // The offset is inside the named layer's source.
    try std.testing.expect(d.offset < doc.layers[d.layer].source.len);
}

test "layers: overlays add tokens, groups and modes; overrides are explicit and re-resolve aliases" {
    var doc = try layered(&.{
        \\{"$version":1,"$modes":{"dim":{"scheme":"dark","fallback":"dark"}},
        \\"tokens":{"color":{"blue":{"900":"#000011ff"}}},
        \\"semantic":{"color":{"zw_ground":{"$light":"{tokens.color.blue.900}","$dim":"#010203ff"},
        \\"accent":{"$override":true,"$value":{"$light":"#a23010ff","$dark":"#e07050ff"}}}}}
    });
    defer doc.deinit();
    if (doc.diagnostic) |d| std.debug.print("{d} {s} {s}\n", .{ d.layer, d.pointer, d.message });
    try std.testing.expect(doc.diagnostic == null);
    try std.testing.expectEqual(@as(usize, 2), doc.layers.len);
    // New semantic token referencing a base group that the overlay extended.
    try std.testing.expectEqual(@as(u32, 0x000011ff), try colorOf(&doc, "light", "color.zw_ground"));
    try std.testing.expectEqual(@as(u32, 0x0000ffff), try colorOf(&doc, "light", "color.blue.500"));
    // New mode from the overlay; its fallback chain reaches dark then light.
    try std.testing.expectEqual(@as(u32, 0x010203ff), try colorOf(&doc, "dim", "color.zw_ground"));
    try std.testing.expectEqual(@as(u32, 0xe07050ff), try colorOf(&doc, "dim", "color.accent"));
    // Override wins, and base aliases of the overridden token follow it.
    try std.testing.expectEqual(@as(u32, 0xa23010ff), try colorOf(&doc, "light", "color.accent"));
    try std.testing.expectEqual(@as(u32, 0xa23010ff), try colorOf(&doc, "light", "color.link"));
    try std.testing.expectEqual(@as(u32, 0xe07050ff), try colorOf(&doc, "hc", "color.link"));
    // Each token remembers the file that declared it last.
    for (doc.tokens) |tok| {
        const want: usize = if (std.mem.eql(u8, tok.path, "color.accent") or std.mem.eql(u8, tok.path, "color.zw_ground") or std.mem.eql(u8, tok.path, "color.blue.900")) 1 else 0;
        try std.testing.expectEqual(want, tok.layer);
    }
}

test "layers: redeclaring a lower layer's token without $override names both declarations" {
    var doc = try layered(&.{
        \\{"$version":1,"semantic":{"color":{"accent":"#ff0000ff"}}}
    });
    defer doc.deinit();
    try expectDiagnostic(&doc, 1, "/semantic/color/accent", "color.accent is already declared at base.json#/semantic/color/accent");
}

test "layers: $override must replace something, must be true, and must stay in its layer" {
    {
        var doc = try layered(&.{
            \\{"$version":1,"semantic":{"color":{"fresh":{"$override":true,"$value":"#ff0000ff"}}}}
        });
        defer doc.deinit();
        try expectDiagnostic(&doc, 1, "/semantic/color/fresh", "no lower layer declares it");
    }
    {
        var doc = try layered(&.{
            \\{"$version":1,"semantic":{"color":{"accent":{"$override":false,"$value":"#ff0000ff"}}}}
        });
        defer doc.deinit();
        try expectDiagnostic(&doc, 1, "/semantic/color/accent/$override", "$override must be true");
    }
    {
        var doc = try layered(&.{
            \\{"$version":1,"tokens":{"color":{"accent":{"$override":true,"$value":"#ff0000ff"}}}}
        });
        defer doc.deinit();
        try expectDiagnostic(&doc, 1, "/tokens/color/accent", "an override must stay in the same layer");
    }
    {
        // A single file (or the base) has nothing below it to override.
        var doc = try resolver.parse(a,
            \\{"$version":1,"tokens":{"color":{"x":{"$override":true,"$value":"#ff0000ff"}}}}
        );
        defer doc.deinit();
        try std.testing.expect(doc.diagnostic != null);
    }
}

test "layers: token/group conflicts and mode conflicts across files" {
    {
        var doc = try layered(&.{
            \\{"$version":1,"tokens":{"color":{"blue":"#ff0000ff"}}}
        });
        defer doc.deinit();
        try expectDiagnostic(&doc, 1, "/tokens/color/blue", "token/group conflict: color.blue; first declaration base.json#/tokens/color/blue");
    }
    {
        var doc = try layered(&.{
            \\{"$version":1,"$modes":{"hc":{"scheme":"light","fallback":"light"}}}
        });
        defer doc.deinit();
        try expectDiagnostic(&doc, 1, "/$modes/hc", "mode hc is already declared at base.json#/$modes/hc");
    }
    {
        var doc = try layered(&.{
            \\{"$version":1,"$modes":{"hc":{"$override":true,"scheme":"light","fallback":"light"}}}
        });
        defer doc.deinit();
        try std.testing.expect(doc.diagnostic == null);
        for (doc.modes) |mode| if (std.mem.eql(u8, mode.name, "hc")) try std.testing.expectEqual(m.Scheme.light, mode.scheme);
    }
    {
        var doc = try layered(&.{
            \\{"$version":1,"$modes":{"new":{"$override":true,"scheme":"dark","fallback":"dark"}}}
        });
        defer doc.deinit();
        try expectDiagnostic(&doc, 1, "/$modes/new", "no lower layer declares it");
    }
}

test "layers: second overlay can override the first; errors point into the right file" {
    {
        var doc = try layered(&.{
            \\{"$version":1,"semantic":{"color":{"zw":"#111111ff"}}}
            ,
            \\{"$version":1,"semantic":{"color":{"zw":{"$override":true,"$value":"#222222ff"}}}}
        });
        defer doc.deinit();
        try std.testing.expect(doc.diagnostic == null);
        try std.testing.expectEqual(@as(u32, 0x222222ff), try colorOf(&doc, "dark", "color.zw"));
    }
    {
        var doc = try layered(&.{
            \\{"$version":1,"semantic":{"color":{"zw":"#111111ff"}}}
            ,
            \\{"$version":1,"semantic":{"color":{"bad":"{semantic.color.nope}"}}}
        });
        defer doc.deinit();
        try expectDiagnostic(&doc, 2, "/semantic/color/bad", "unknown token reference");
    }
    {
        // Only the base must declare `tokens`.
        var doc = try resolver.parseLayers(a, &.{ .{ .name = "base.json", .source = "{\"$version\":1}" } });
        defer doc.deinit();
        try expectDiagnostic(&doc, 0, "", "missing required field: tokens");
    }
}

test "layers: allocation failures leave no leaks" {
    try std.testing.checkAllAllocationFailures(a, struct {
        fn probe(allocator: std.mem.Allocator) !void {
            var doc = try resolver.parseLayers(allocator, &.{
                .{ .name = "base.json", .source = base_layer },
                .{ .name = "app.json", .source = "{\"$version\":1,\"semantic\":{\"color\":{\"zw\":\"{semantic.color.accent}\",\"accent\":{\"$override\":true,\"$value\":\"#123456\"}}}}" },
            });
            doc.deinit();
        }
    }.probe, .{});
}
