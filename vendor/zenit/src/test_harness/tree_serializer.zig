/// tree_serializer: Node tree -> JSON serialization.
/// Recursively traverse UI node tree, output JSON for AI agent consumption.
/// (zenit v0.5 compat: uses meta.ownership.meta.test_id / behavior.interaction.focusable /
/// visuals.content.text / frame_state.rect paths).
const std = @import("std");
const ui = @import("ui");
const Node = ui.Node;
const ComputedRect = ui.ComputedRect;
const JsonWriter = @import("json_writer.zig").JsonWriter;
const OverlayStack = @FieldType(ui.Cx, "overlay_stack");

/// Recursion guard, not a product limit. Real apps nest well past 20 levels
/// (an App wraps the user root, window headers and editors add more), and
/// the guard also stops queryByTestId/findByTestId silently, so keep it far
/// above realistic depth. Output size is bounded separately (TreeTooLarge).
const MAX_DEPTH = 64;

// -- zenit v0.5 field access helpers --

inline fn nodeTestId(node: *const Node) ?[]const u8 {
    return node.meta.ownership.meta.test_id;
}

inline fn nodeComponentName(node: *const Node) ?[]const u8 {
    return node.meta.ownership.meta.component_name;
}

inline fn nodeFocusable(node: *const Node) bool {
    return node.behavior.interaction.focusable;
}

inline fn nodeText(node: *const Node) ?ui.TextProps {
    return node.getText();
}

inline fn nodeRect(node: *const Node) ComputedRect {
    return node.rectFromWorldOrFallback();
}

fn writeColorRgba(jw: *JsonWriter, color: ui.Color) void {
    var buf: [32]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{d},{d},{d},{d}", .{ color.r, color.g, color.b, color.a }) catch return;
    jw.stringValue(text);
}

/// Serialize entire node tree to JSON buffer. `overlays`: overlay stack for this Cx; nodes in
/// suspended layers are hidden (see effectiveOpacity).
pub fn serializeTree(root: *Node, overlays: ?*const OverlayStack, buf: []u8) error{TreeTooLarge}![]const u8 {
    var jw = JsonWriter.init(buf);
    serializeNode(&jw, root, overlays, 0, false);
    if (jw.hasOverflowed()) return error.TreeTooLarge;
    return jw.getWritten();
}

/// Frame archives need opacity on descendants too: portaled/suspended layer
/// visibility cannot always be inferred from the physical parent chain.
pub fn serializeFrameTree(root: *Node, overlays: ?*const OverlayStack, buf: []u8) error{TreeTooLarge}![]const u8 {
    var jw = JsonWriter.init(buf);
    serializeNode(&jw, root, overlays, 0, true);
    if (jw.hasOverflowed()) return error.TreeTooLarge;
    return jw.getWritten();
}

/// Find nodes by test_id; return JSON of matches.
pub fn queryByTestId(root: *Node, overlays: ?*const OverlayStack, test_id: []const u8, buf: []u8) error{TreeTooLarge}![]const u8 {
    var jw = JsonWriter.init(buf);
    jw.beginArray();
    queryByTestIdRecursive(&jw, root, overlays, test_id, 0);
    jw.endArray();
    if (jw.hasOverflowed()) return error.TreeTooLarge;
    return jw.getWritten();
}

/// A scoped / filtered `/tree` read (POST /tree): start at the first node with `root_test_id`
/// (null = the whole tree) and, with `visible_only`, leave out every subtree that cannot show —
/// see `childShown`. Unfiltered output is byte-identical to `serializeTree` / a `/query` match.
pub const TreeQuery = struct {
    root_test_id: ?[]const u8 = null,
    visible_only: bool = false,
};

pub fn serializeTreeQuery(root: *Node, overlays: ?*const OverlayStack, query: TreeQuery, buf: []u8) error{ TreeTooLarge, NotFound }![]const u8 {
    const start = if (query.root_test_id) |id| findQueryRoot(root, overlays, id, query.visible_only) orelse return error.NotFound else root;
    var jw = JsonWriter.init(buf);
    serializeNodeFiltered(&jw, start, overlays, 0, false, if (query.visible_only) narrowClip(start, ancestorClip(root, start)) else null);
    if (jw.hasOverflowed()) return error.TreeTooLarge;
    return jw.getWritten();
}

/// First node with the test id; a visible-only read prefers the first one that shows.
fn findQueryRoot(root: *Node, overlays: ?*const OverlayStack, test_id: []const u8, visible_only: bool) ?*Node {
    const first = findByTestId(root, test_id) orelse return null;
    if (!visible_only or effectiveOpacity(first, overlays) > 0) return first;
    return findShownByTestId(root, overlays, test_id, 0) orelse first;
}

fn findShownByTestId(node: *Node, overlays: ?*const OverlayStack, test_id: []const u8, depth: usize) ?*Node {
    if (depth > MAX_DEPTH) return null;
    if (nodeTestId(node)) |tid| {
        if (std.mem.eql(u8, tid, test_id) and effectiveOpacity(node, overlays) > 0) return node;
    }
    for (node.children.items) |child| if (findShownByTestId(child, overlays, test_id, depth + 1)) |found| return found;
    return null;
}

/// Window-space rectangle a subtree can paint into.
pub const Clip = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,

    fn of(r: ComputedRect) Clip {
        return .{ .x = r.x, .y = r.y, .w = @max(0, r.w), .h = @max(0, r.h) };
    }
    fn intersect(a: Clip, b: Clip) Clip {
        const x0 = @max(a.x, b.x);
        const y0 = @max(a.y, b.y);
        const x1 = @min(a.x + a.w, b.x + b.w);
        const y1 = @min(a.y + a.h, b.y + b.h);
        return .{ .x = x0, .y = y0, .w = @max(0, x1 - x0), .h = @max(0, y1 - y0) };
    }
    fn overlaps(a: Clip, r: ComputedRect) bool {
        return r.x < a.x + a.w and r.x + r.w > a.x and r.y < a.y + a.h and r.y + r.h > a.y;
    }
};

/// The clip in force at `node` (exclusive): the tree root's box narrowed by every clipping
/// ancestor between them.
fn ancestorClip(root: *Node, node: *Node) Clip {
    var clip = Clip.of(root.globalRect());
    var chain: [MAX_DEPTH + 2]*Node = undefined;
    var n: usize = 0;
    var cur = node.parent;
    while (cur) |p| : (cur = p.parent) {
        if (n == chain.len) break;
        chain[n] = p;
        n += 1;
    }
    while (n > 0) {
        n -= 1;
        clip = narrowClip(chain[n], clip);
    }
    return clip;
}

/// The clip for a node's children: its own box when it clips (overflow hidden).
fn narrowClip(node: *Node, clip: Clip) Clip {
    if (!node.style.overflow_hidden) return clip;
    return clip.intersect(Clip.of(node.globalRect()));
}

/// Whether a child (and so its subtree) can show in a visible-only read. Left out: display none;
/// opacity 0; inside a suspended overlay layer; a clipping box collapsed to 0 (the render engine
/// skips those subtrees); an empty box without children; a box lying wholly outside the clip with
/// nothing inside it that reaches back into the clip (scrolled-away rows, closed panels).
fn childShown(node: *Node, overlays: ?*const OverlayStack, clip: Clip) bool {
    if (node.style.display == .none) return false;
    if (node.getOpacity() == 0) return false;
    if (overlays) |stack| if (stack.isNodeInSuspendedLayer(node)) return false;
    const r = node.globalRect();
    const empty = r.w <= 0.1 or r.h <= 0.1;
    if (node.style.overflow_hidden and empty) return false;
    if (empty and node.children.items.len == 0) return false;
    if (!empty and clip.overlaps(r)) return true;
    if (node.style.overflow_hidden) return false;
    return reachesClip(node, clip, 0);
}

/// Some descendant of a non-clipping box paints inside the clip (an absolute child escaping an
/// off-screen or empty parent).
fn reachesClip(node: *Node, clip: Clip, depth: usize) bool {
    if (depth > MAX_DEPTH) return false;
    for (node.children.items) |child| {
        if (child.style.display == .none or child.getOpacity() == 0) continue;
        const r = child.globalRect();
        const empty = r.w <= 0.1 or r.h <= 0.1;
        if (!empty and clip.overlaps(r)) return true;
        if (child.style.overflow_hidden) continue;
        if (reachesClip(child, clip, depth + 1)) return true;
    }
    return false;
}

/// Find single node by test_id; return pointer.
pub fn findByTestId(root: *Node, test_id: []const u8) ?*Node {
    return findByTestIdRecursive(root, test_id, 0);
}

fn findByTestIdRecursive(node: *Node, test_id: []const u8, depth: usize) ?*Node {
    if (depth > MAX_DEPTH) return null;
    if (nodeTestId(node)) |tid| {
        if (std.mem.eql(u8, tid, test_id)) return node;
    }
    const children = node.children.items;
    for (children) |child| {
        if (findByTestIdRecursive(child, test_id, depth + 1)) |found| {
            return found;
        }
    }
    return null;
}

fn queryByTestIdRecursive(jw: *JsonWriter, node: *Node, overlays: ?*const OverlayStack, test_id: []const u8, depth: usize) void {
    if (depth > MAX_DEPTH) return;
    if (nodeTestId(node)) |tid| {
        if (std.mem.eql(u8, tid, test_id)) {
            serializeNode(jw, node, overlays, 0, false);
        }
    }
    const children = node.children.items;
    for (children) |child| {
        queryByTestIdRecursive(jw, child, overlays, test_id, depth + 1);
    }
}

/// Condensed layout summary: output only nodes with test_id / component_name / text / or focusable.
pub fn serializeLayout(root: *Node, buf: []u8) []const u8 {
    var jw = JsonWriter.init(buf);
    jw.beginArray();
    serializeLayoutRecursive(&jw, root, 0, 0);
    jw.endArray();
    return jw.getWritten();
}

fn isInterestingNode(node: *Node) bool {
    if (nodeTestId(node) != null) return true;
    if (nodeComponentName(node) != null) return true;
    if (nodeFocusable(node)) return true;
    if (nodeText(node)) |t| {
        if (t.content.len > 0) return true;
    }
    return false;
}

fn serializeLayoutRecursive(jw: *JsonWriter, node: *Node, depth: usize, indent: usize) void {
    if (depth > MAX_DEPTH) return;
    const rect = nodeRect(node);
    if (rect.w <= 0 or rect.h <= 0 or node.getOpacity() == 0) return;

    if (isInterestingNode(node)) {
        const global = node.globalRect();
        jw.beginObject();
        if (nodeTestId(node)) |tid| {
            jw.key("test_id");
            jw.stringValue(tid);
        }
        if (nodeComponentName(node)) |cn| {
            jw.key("component");
            jw.stringValue(cn);
        }
        jw.key("tag");
        jw.stringValue(@tagName(node.tag));
        jw.key("rect");
        jw.beginObject();
        jw.key("x");
        jw.floatValue(global.x);
        jw.key("y");
        jw.floatValue(global.y);
        jw.key("w");
        jw.floatValue(global.w);
        jw.key("h");
        jw.floatValue(global.h);
        jw.endObject();
        if (nodeFocusable(node)) {
            jw.key("focusable");
            jw.booleanValue(true);
        }
        if (nodeText(node)) |t| {
            if (t.content.len > 0) {
                jw.key("text");
                const tlen = @min(t.content.len, 100);
                jw.stringValue(t.content[0..tlen]);
                if (t.font_size != 14) {
                    jw.key("font_size");
                    jw.floatValue(t.font_size);
                }
                if (t.font_weight != 400) {
                    jw.key("font_weight");
                    jw.numberValue(@intCast(t.font_weight));
                }
                if (t.use_italic_font) {
                    jw.key("italic");
                    jw.booleanValue(true);
                }
            }
        }
        if (node.getOpacity() != 1.0) {
            jw.key("opacity");
            jw.floatValue(node.getOpacity());
        }
        if (node.style.translate_x != 0 or node.style.translate_y != 0) {
            jw.key("translate_x");
            jw.floatValue(node.style.translate_x);
            jw.key("translate_y");
            jw.floatValue(node.style.translate_y);
        }
        if (node.getBackground().a > 0) {
            jw.key("has_bg");
            jw.booleanValue(true);
            jw.key("bg_rgba");
            writeColorRgba(jw, node.getBackground());
        }
        if (node.children.items.len > 0) {
            jw.key("children_count");
            jw.numberValue(@intCast(node.children.items.len));
        }
        jw.key("depth");
        jw.numberValue(@intCast(indent));
        jw.endObject();
    }

    const children = node.children.items;
    for (children) |child| {
        serializeLayoutRecursive(jw, child, depth + 1, indent + 1);
    }
}

/// Effective opacity: self × all ancestor opacities. Nodes render as invisible (opacity 0) when:
/// - Self or ancestor has display:none;
/// - Falls under content/barrier subtree of suspended (closed) overlay layer. Modal close shrinks
///   barrier to 0x0 + overflow_hidden + suspend layer; dialog and ancestor opacity remain 1;
/// - Self or ancestor overflow_hidden with box collapsed to 0 width/height. Render engine skips
///   entire subtree by same criteria (render_engine/tick.zig `overflow_hidden and w/h <= 0.1`);
///   clipping applies to absolute/z_index children too (only portal escapes).
pub fn effectiveOpacity(node: *Node, overlays: ?*const OverlayStack) f32 {
    if (overlays) |stack| {
        if (stack.isNodeInSuspendedLayer(node)) return 0;
    }
    var o: f32 = 1;
    var cur: ?*Node = node;
    while (cur) |n| : (cur = n.parent) {
        if (n.style.display == .none) return 0;
        if (n.style.overflow_hidden) {
            const r = nodeRect(n);
            if (r.w <= 0.1 or r.h <= 0.1) return 0;
        }
        o *= n.getOpacity();
    }
    return o;
}

fn serializeNode(jw: *JsonWriter, node: *Node, overlays: ?*const OverlayStack, depth: usize, all_effective: bool) void {
    serializeNodeFiltered(jw, node, overlays, depth, all_effective, null);
}

/// `clip`: when set (a visible-only read), children that cannot show are left out (see
/// `childShown`) and each child gets the clip narrowed by its clipping ancestors.
fn serializeNodeFiltered(jw: *JsonWriter, node: *Node, overlays: ?*const OverlayStack, depth: usize, all_effective: bool, clip: ?Clip) void {
    if (depth > MAX_DEPTH) {
        jw.null_();
        return;
    }

    const global = node.globalRect();
    jw.beginObject();

    jw.key("id");
    jw.numberValue(@intCast(node.id));

    jw.key("tag");
    jw.stringValue(@tagName(node.tag));

    if (nodeTestId(node)) |tid| {
        jw.key("test_id");
        jw.stringValue(tid);
    }

    if (nodeComponentName(node)) |cn| {
        jw.key("component");
        jw.stringValue(cn);
    }

    // display:none: node remains in tree but doesn't render; queries exclude by this.
    if (node.style.display == .none) {
        jw.key("hidden");
        jw.booleanValue(true);
    }

    // Query results include "effective opacity" for top-level hits (self × ancestors; display:none
    // = 0). When layer transitions fade in on ancestors, tests wait for "truly fully visible"
    // rather than guessing sleep duration.
    if (depth == 0 or all_effective) {
        jw.key("effective_opacity");
        jw.floatValue(effectiveOpacity(node, overlays));
    }

    jw.key("rect");
    jw.beginObject();
    jw.key("x");
    jw.floatValue(global.x);
    jw.key("y");
    jw.floatValue(global.y);
    jw.key("w");
    jw.floatValue(global.w);
    jw.key("h");
    jw.floatValue(global.h);
    jw.endObject();

    const transform = node.worldTransform();
    jw.key("world_transform");
    jw.beginArray();
    for ([_]f32{ transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty }) |value| jw.floatValue(value);
    jw.endArray();

    if (nodeText(node)) |t| {
        if (t.content.len > 0) {
            jw.key("text");
            if (t.content.len > 200) {
                jw.stringValue(t.content[0..200]);
            } else {
                jw.stringValue(t.content);
            }
        }
    }

    // Paint facts a test compares across widgets (one look): own background, text size / colour,
    // icon tint. Only written when present, so plain boxes stay as small as before.
    if (node.getBackground().a > 0) {
        jw.key("bg_rgba");
        writeColorRgba(jw, node.getBackground());
    }
    if (nodeText(node)) |t| {
        if (t.content.len > 0) {
            jw.key("font_size");
            jw.floatValue(t.font_size);
            jw.key("text_rgba");
            writeColorRgba(jw, t.color);
        }
    }
    if (node.getIcon()) |icon| {
        jw.key("icon_rgba");
        writeColorRgba(jw, icon.tint);
    }

    if (node.getOpacity() != 1.0) {
        jw.key("opacity");
        jw.floatValue(node.getOpacity());
    }
    if (node.style.translate_x != 0 or node.style.translate_y != 0) {
        jw.key("translate_x");
        jw.floatValue(node.style.translate_x);
        jw.key("translate_y");
        jw.floatValue(node.style.translate_y);
    }
    if (@abs(node.style.scale_x() - 1) > 0.0001 or @abs(node.style.scale_y() - 1) > 0.0001) {
        jw.key("scale_x");
        jw.floatValue(node.style.scale_x());
        jw.key("scale_y");
        jw.floatValue(node.style.scale_y());
    }
    if (@abs(node.style.rotate()) > 0.0001) {
        jw.key("rotate");
        jw.floatValue(node.style.rotate());
    }

    if (nodeFocusable(node)) {
        jw.key("focusable");
        jw.booleanValue(true);
    }

    const rect = nodeRect(node);
    const visible = rect.w > 0 and rect.h > 0 and node.getOpacity() != 0;
    if (!visible) {
        jw.key("visible");
        jw.booleanValue(false);
    }

    const children = node.children.items;
    if (children.len > 0) {
        jw.key("children");
        jw.beginArray();
        // Full output: previously capped at 50 children per layer (list tails "not found"; client
        // never handled truncated flag, silently lost). Caller buffers size; overflow errors
        // explicitly.
        for (children) |child| {
            if (clip) |c| {
                if (!childShown(child, overlays, c)) continue;
                serializeNodeFiltered(jw, child, overlays, depth + 1, all_effective, narrowClip(child, c));
            } else serializeNode(jw, child, overlays, depth + 1, all_effective);
        }
        jw.endArray();
    }

    jw.endObject();
}

// -- Tests --

const testing = std.testing;

fn queryEffectiveOpacity(root: *Node, overlays: ?*const OverlayStack, test_id: []const u8) !f64 {
    var buf: [256 * 1024]u8 = undefined;
    const json = try queryByTestId(root, overlays, test_id, &buf);
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, json, .{});
    defer parsed.deinit();
    const items = parsed.value.array.items;
    try testing.expectEqual(@as(usize, 1), items.len);
    const v = items[0].object.get("effective_opacity") orelse return error.TestUnexpectedResult;
    return switch (v) {
        .float => |f| f,
        .integer => |i| @floatFromInt(i),
        else => error.TestUnexpectedResult,
    };
}

fn pumpFrames(ctx: *ui.Cx, n: usize) void {
    for (0..n) |_| {
        ctx.frame_time_ms += 16;
        ctx.layout();
        _ = ctx.render();
    }
}

test "effective_opacity: 关闭的 Modal 内容计 0，打开后计 1，关回去再计 0" {
    const allocator = testing.allocator;
    var ctx = try ui.Cx.init(allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(800, 600);
    const root = try ui.box(ctx, .{ .width = .{ .px = 800 }, .height = .{ .px = 600 } }, .{});
    ctx.root = root;
    const scope = try ui.Scope.init(allocator, null, ctx.owner);
    defer scope.dispose();
    const vis = try scope.createSignal(bool, false);
    const result = try ui.widgets.Modal(.{ .title = "Probe", .open = vis }).mount(scope, ctx);
    if (!result.portaled) try root.appendChild(allocator, result.overlay);
    result.dialog.meta.ownership.meta.test_id = "probe.dialog";

    // Initially closed: barrier 0x0 + layer suspended, but dialog and ancestor opacity all 1.
    pumpFrames(ctx, 3);
    try testing.expectEqual(@as(f64, 0), try queryEffectiveOpacity(root, &ctx.overlay_stack, "probe.dialog"));

    vis.set(true);
    pumpFrames(ctx, 60);
    try testing.expectApproxEqAbs(@as(f64, 1), try queryEffectiveOpacity(root, &ctx.overlay_stack, "probe.dialog"), 0.001);

    vis.set(false);
    pumpFrames(ctx, 60);
    try testing.expectEqual(@as(f64, 0), try queryEffectiveOpacity(root, &ctx.overlay_stack, "probe.dialog"));
}

test "effective_opacity: 挂起层里的节点计 0（与几何无关）" {
    const allocator = testing.allocator;
    var stack = OverlayStack{ .allocator = std.testing.allocator };
    defer stack.deinit();
    const handle = try stack.push(.{ .kind = .non_modal, .enter_transition = .none, .exit_transition = .none });
    const content = try Node.create(allocator, 901, .box, .{ .width = .{ .px = 120 }, .height = .{ .px = 60 } });
    defer content.destroy(allocator);
    const child = try Node.create(allocator, 902, .box, .{ .width = .{ .px = 80 }, .height = .{ .px = 24 } });
    try content.appendChild(allocator, child);
    stack.bindFloatingContent(allocator, handle, content);

    try testing.expectEqual(@as(f32, 1), effectiveOpacity(child, &stack));
    // Suspend alone (no opacity/size change): still counts as 0.
    stack.findLayer(handle).?.suspended = true;
    try testing.expectEqual(@as(f32, 0), effectiveOpacity(child, &stack));
    try testing.expectEqual(@as(f32, 0), effectiveOpacity(content, &stack));
    // Without overlay stack, degrades to pure node check.
    try testing.expectEqual(@as(f32, 1), effectiveOpacity(child, null));

    // A frame archive must carry the suspended-layer visibility on descendants,
    // even though their physical parent opacity remains one.
    var buffer: [8192]u8 = undefined;
    const archived = try serializeFrameTree(content, &stack, &buffer);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, archived, .{});
    defer parsed.deinit();
    const descendants = parsed.value.object.get("children").?.array.items;
    try testing.expectEqual(@as(usize, 1), descendants.len);
    const opacity = descendants[0].object.get("effective_opacity") orelse return error.TestUnexpectedResult;
    const value: f64 = switch (opacity) {
        .float => |f| f,
        .integer => |i| @floatFromInt(i),
        else => return error.TestUnexpectedResult,
    };
    try testing.expectEqual(@as(f64, 0), value);
    var too_small: [16]u8 = undefined;
    try testing.expectError(error.TreeTooLarge, serializeFrameTree(content, &stack, &too_small));
}

test "effective_opacity: 0×0 的 overflow_hidden 祖先把子树计 0" {
    const allocator = testing.allocator;
    var ctx = try ui.Cx.init(allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(400, 300);
    const root = try ui.box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;
    const clipper = try ui.box(ctx, .{ .width = .{ .px = 0 }, .height = .{ .px = 0 } }, .{});
    clipper.style.overflow_hidden = true;
    try root.appendChild(allocator, clipper);
    const leaf = try ui.box(ctx, .{ .width = .{ .px = 50 }, .height = .{ .px = 20 } }, .{});
    try clipper.appendChild(allocator, leaf);
    pumpFrames(ctx, 1);
    try testing.expectEqual(@as(f32, 0), effectiveOpacity(leaf, null));

    // Control: same 0x0 but no clip; children still overflow visible.
    clipper.style.overflow_hidden = false;
    clipper.markRenderDirty();
    pumpFrames(ctx, 1);
    try testing.expectEqual(@as(f32, 1), effectiveOpacity(leaf, null));
}

test "deep trees: nodes 30 levels down are serialized and found by test id" {
    const allocator = testing.allocator;
    var ctx = try ui.Cx.init(allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(400, 300);
    const root = try ui.box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;
    var parent = root;
    for (0..30) |_| {
        const child = try ui.box(ctx, .{}, .{});
        try parent.appendChild(allocator, child);
        parent = child;
    }
    parent.meta.ownership.meta.test_id = "probe.deep";
    pumpFrames(ctx, 1);

    try testing.expect(findByTestId(root, "probe.deep") == parent);
    const buf = try allocator.alloc(u8, 256 * 1024);
    defer allocator.free(buf);
    const json = try serializeTree(root, null, buf);
    try testing.expect(std.mem.indexOf(u8, json, "null") == null);
    try testing.expect(std.mem.indexOf(u8, json, "probe.deep") != null);
}

test "query nodes report their paint facts: background, text size and colour, icon tint" {
    const allocator = testing.allocator;
    var ctx = try ui.Cx.init(allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(400, 300);
    const root = try ui.box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;
    const row = try ui.box(ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 28 }, .background = ui.Color.hex(0x112233) }, .{});
    row.meta.ownership.meta.test_id = "probe.row";
    try root.appendChild(allocator, row);
    const label = try ui.text(ctx, "Copy", .{ .font_size = 13, .color = ui.Color.hex(0xaabbcc) });
    try row.appendChild(allocator, label);
    const plain = try ui.box(ctx, .{ .width = .{ .px = 10 }, .height = .{ .px = 10 } }, .{});
    plain.meta.ownership.meta.test_id = "probe.plain";
    try root.appendChild(allocator, plain);
    pumpFrames(ctx, 1);
    const buf = try allocator.alloc(u8, 64 * 1024);
    defer allocator.free(buf);
    const json = try queryByTestId(root, null, "probe.row", buf);
    try testing.expect(std.mem.indexOf(u8, json, "\"bg_rgba\":\"17,34,51,255\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"font_size\":13") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"text_rgba\":\"170,187,204,255\"") != null);
    const bare = try queryByTestId(root, null, "probe.plain", buf);
    try testing.expect(std.mem.indexOf(u8, bare, "bg_rgba") == null);
}

test "tree query: a subtree by test id, unfiltered = the /query match, unknown root = NotFound" {
    const allocator = testing.allocator;
    var ctx = try ui.Cx.init(allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(400, 300);
    const root = try ui.box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;
    const panel = try ui.box(ctx, .{ .width = .{ .px = 200 }, .height = .{ .px = 100 } }, .{});
    panel.meta.ownership.meta.test_id = "probe.panel";
    try root.appendChild(allocator, panel);
    try panel.appendChild(allocator, try ui.text(ctx, "inside", .{}));
    const other = try ui.text(ctx, "outside", .{});
    try root.appendChild(allocator, other);
    pumpFrames(ctx, 1);
    const buf = try allocator.alloc(u8, 64 * 1024);
    defer allocator.free(buf);
    const qbuf = try allocator.alloc(u8, 64 * 1024);
    defer allocator.free(qbuf);
    const json = try serializeTreeQuery(root, null, .{ .root_test_id = "probe.panel" }, buf);
    try testing.expect(std.mem.indexOf(u8, json, "inside") != null);
    try testing.expect(std.mem.indexOf(u8, json, "outside") == null);
    const matched = try queryByTestId(root, null, "probe.panel", qbuf);
    // `/query` wraps its matches in an array: same object inside.
    try testing.expectEqualStrings(matched[1 .. matched.len - 1], json);
    // Whole tree unfiltered = GET /tree.
    const whole = try serializeTreeQuery(root, null, .{}, buf);
    try testing.expectEqualStrings(try serializeTree(root, null, qbuf), whole);
    try testing.expectError(error.NotFound, serializeTreeQuery(root, null, .{ .root_test_id = "probe.none" }, buf));
}

test "tree query visible_only: hidden, transparent, collapsed, empty and scrolled-away subtrees are left out" {
    const allocator = testing.allocator;
    var ctx = try ui.Cx.init(allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(400, 300);
    const root = try ui.box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 }, .direction = .column }, .{});
    ctx.root = root;
    const scope = try ui.Scope.init(allocator, null, ctx.owner);
    defer scope.dispose();

    const shown = try ui.text(ctx, "shown", .{});
    try root.appendChild(allocator, shown);
    const hidden = try ui.text(ctx, "hidden-display", .{});
    hidden.setDisplay(.none);
    try root.appendChild(allocator, hidden);
    const faded = try ui.box(ctx, .{ .width = .{ .px = 50 }, .height = .{ .px = 20 }, .opacity = 0 }, .{});
    try faded.appendChild(allocator, try ui.text(ctx, "faded", .{}));
    try root.appendChild(allocator, faded);
    const collapsed = try ui.box(ctx, .{ .width = .{ .px = 0 }, .height = .{ .px = 0 } }, .{});
    collapsed.style.overflow_hidden = true;
    try collapsed.appendChild(allocator, try ui.text(ctx, "collapsed", .{}));
    try root.appendChild(allocator, collapsed);
    try root.appendChild(allocator, try ui.box(ctx, .{ .width = .{ .px = 0 }, .height = .{ .px = 0 } }, .{}));
    // A zero-size non-clipping box keeps a child that still paints (absolute escape).
    const holder = try ui.box(ctx, .{ .width = .{ .px = 0 }, .height = .{ .px = 0 } }, .{});
    const escaped = try ui.box(ctx, .{ .position = .absolute, .width = .{ .px = 40 }, .height = .{ .px = 20 } }, .{});
    escaped.meta.ownership.meta.test_id = "probe.escaped";
    try holder.appendChild(allocator, escaped);
    try root.appendChild(allocator, holder);
    // A 100-tall list of ten 40-tall rows (label in each row's top half) scrolled to 150: row 3
    // shows only its empty bottom half, so the labels in view are rows 4..6.
    const list = try ui.widgets.ScrollArea(.{ .height = 100, .width = 200 }).mount(scope, ctx);
    list.container.meta.ownership.meta.test_id = "probe.list";
    try root.appendChild(allocator, list.container);
    var names: [10][8]u8 = undefined;
    for (0..10) |i| {
        const row = try ui.box(ctx, .{ .width = .{ .grow = .{} }, .height = .{ .px = 40 } }, .{});
        try row.appendChild(allocator, try ui.text(ctx, try std.fmt.bufPrint(&names[i], "row-{d}", .{i}), .{}));
        try list.content.appendChild(allocator, row);
    }
    pumpFrames(ctx, 2);
    ui.widgets.setScrollY(list.state, list.content, 150);
    list.content.style.translate_y = -150;
    pumpFrames(ctx, 2);

    const buf = try allocator.alloc(u8, 128 * 1024);
    defer allocator.free(buf);
    const all = try serializeTreeQuery(root, &ctx.overlay_stack, .{}, buf);
    for ([_][]const u8{ "shown", "hidden-display", "faded", "collapsed", "row-0", "row-9" }) |word| try testing.expect(std.mem.indexOf(u8, all, word) != null);
    const full_len = all.len;
    const vis = try serializeTreeQuery(root, &ctx.overlay_stack, .{ .visible_only = true }, buf);
    try testing.expect(vis.len < full_len);
    for ([_][]const u8{ "shown", "probe.escaped", "row-4", "row-5", "row-6" }) |word| {
        if (std.mem.indexOf(u8, vis, word) == null) {
            std.debug.print("missing {s}\n", .{word});
            return error.TestUnexpectedResult;
        }
    }
    for ([_][]const u8{ "hidden-display", "faded", "collapsed", "row-0", "row-1", "row-2", "row-3", "row-7", "row-8", "row-9" }) |word| {
        if (std.mem.indexOf(u8, vis, word) != null) {
            std.debug.print("unexpected {s}\n", .{word});
            return error.TestUnexpectedResult;
        }
    }
    // Scoped + visible: only the list's rows in view.
    const scoped = try serializeTreeQuery(root, &ctx.overlay_stack, .{ .root_test_id = "probe.list", .visible_only = true }, buf);
    try testing.expect(std.mem.indexOf(u8, scoped, "shown") == null);
    try testing.expect(std.mem.indexOf(u8, scoped, "row-4") != null);
    try testing.expect(std.mem.indexOf(u8, scoped, "row-0") == null);
}
