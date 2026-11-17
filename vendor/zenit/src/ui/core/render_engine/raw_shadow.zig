//! Raw-state shadow verification of undeclared before_render hooks ("verified trust").
//!
//! A `.subtree` hook (and a `main` hook) may write its subtree raw: Raw setters, `node.style.*` /
//! ext fields, World paint state, content (text / icon / image, a borrowed text buffer in place),
//! layout output, `children.items`. No dirty bit shows those writes, so today such a subtree is
//! hook-owned: re-recorded every frame, its ancestors never spliced or memoized.
//!
//! This module keeps, for every node of such a subtree, a copy of the raw state the paint pass
//! reads (`Shadow`, the fields listed below). Once per frame, right before the paint pass (after
//! the tick, the post-tick layout and pass-1.5 layout), `verifyFrame` compares every node with
//! its shadow; a difference becomes dirty bits (node_dirty.markUnmarkedRenderChange: render + composite, never
//! layout, the visible effect today's full re-record has), the shadow is refreshed. After the walk
//! every change since the last paint, by the hook, an event handler, a timer or anything else, is
//! visible in the dirty bits, which is the contract a `.dirty_marking` hook gives: the hook node
//! is cache-trusted for this frame (hookTrustedThisFrame / untrustedHookSubtreeThisFrame, read by
//! the render engine where it used to read Node.beforeRenderHooksCacheTrusted and the
//! has_untrusted_before_render_subtree flag).
//!
//! Nodes whose render input the shadow cannot hold are unverifiable and marked dirty every frame
//! (so re-recorded, and no subtree cache of an ancestor includes them), like a node that changes
//! every frame: custom draw, custom clip provider, path / stroke / custom-clip geometry, a glass
//! group (shared pointer), text longer than `max_text_bytes` or with more than `max_spans` spans.
//! A nested `main` hook node (component hooks, `before_render.main`) keeps today's path for its
//! subtree: it stays untrusted, so does every ancestor's subtree cache.
//!
//! Freshness: a shadow is only trusted when it was refreshed by the previous verification pass of
//! the same Cx (`Shadow.seq`) and generation; anything else (first sight, a pass that skipped the
//! node, an aborted pass) counts as a change, which re-records the node and invalidates every cache
//! that contains it. A pass aborts (the hook stays untrusted this frame, today's path) past
//! `max_nodes_per_pass` nodes or on OOM, and then bumps the generation.
//!
//! Trust is per frame and per Cx (`Current`: the Cx's World id and pass seq, installed by
//! Cx.render around its own paint only). When a hook that the previous pass trusted is not trusted
//! now (it became excluded, the pass aborted, verification was switched off), every cross-frame
//! cache inside its subtree and every memo / subtree payload of its ancestors is dropped
//! (dropHookCaches): they were recorded under a trust this frame does not have. The render engine
//! also never replays a memo of a hook-owned or volatile node (mod.zig buildRetainedSubtree).
//!
//! ZENIT_DISABLE_HOOK_VERIFY=1 turns it off: no shadow is created and no hook is trusted by
//! verification, so every undeclared hook takes today's path, with one deliberate difference: an
//! overlay root (z_index > 0) with a `main` hook no longer keeps its promoted / legacy overflow
//! cache (mod.zig buildNodeExecutionPlan overlay_root_before_render_cache_safe requires a verified
//! hook; today's path kept it and replayed raw writes of its subtree stale). Popover and similar
//! overlays then re-record their surface every frame. The P1 translate fast path and the memo /
//! reparent fixes are independent of this switch.
//!
//! Covered state (audited at comptime below: a new field of any listed struct, a new pointer
//! anywhere inside them, or a new BoxStyle field fails to compile until it is classified here):
//! - `Node.style` (Style), all bytes; `Style.ext` pointee (StyleExt), all bytes. translate_x /
//!   translate_y are compared separately (a translate-only change already marked by
//!   markOwnTranslationDirty / composite needs nothing more).
//! - World paint state (PaintStateData: background, opacity).
//! - World layout rect (what RenderContext.rectFromWorld returns), the layout output
//!   (NodeLayoutOutput) bytes, and the layout-output slot revision (storeTextLayout rewrites the
//!   TextLayout in place, behind the same pointer).
//! - Content: TextProps bytes plus the bytes of `content` and the values of `spans`; IconProps,
//!   ImageProps bytes.
//! - `Node.children` (the pointer sequence), `Node.tag`, `NodeFlags` (all bits but out_of_viewport,
//!   which only the tick reads), the sticky offset
//!   (NodeRuntime.sticky), the custom draw / clip hooks and the before_render hook list (identity).
//! - Inherited text style (StyleExt.text_color / text_font_size / text_font_weight): a change marks
//!   every descendant too (resolveTextProps reads ancestors).
//! Not covered, by design (they have their own invalidation, which the paint pass reads every
//! frame): animation state (NodeRuntime linger / transitions / commands, manual animation flags),
//! cache bookkeeping (meta.per_frame.caches), ids, event / hit / a11y state. Pointees reached only
//! through a pointer held by identity (TextLayout, icon Rep shapes, GridConfig) are trusted not to
//! be edited in place (see `pointer_policy`).
const std = @import("std");
const builtin = @import("builtin");
const reflection = @import("zenit_reflection");
const types = @import("../types.zig");
const node_mod = @import("../node.zig");
const nlo = @import("../node_layout_output.zig");
const world_mod = @import("../world.zig");
const paint_state_table = @import("../paint_state_table.zig");
const node_dirty = @import("../node_dirty.zig");
const node_render_cache = @import("../node_render_cache.zig");

const Allocator = std.mem.Allocator;
const Node = node_mod.Node;
const Style = types.Style;
const StyleExt = types.StyleExt;
const TextProps = types.TextProps;
const TextSpan = types.TextSpan;
const IconProps = types.IconProps;
const ImageProps = types.ImageProps;
const ComputedRect = types.ComputedRect;
const PaintStateData = paint_state_table.PaintStateData;

/// Text longer than this is not copied: the node is unverifiable.
pub const max_text_bytes: usize = 4096;
pub const max_spans: usize = 256;
/// Nodes one verification pass may compare before it gives up (today's path for the hook).
pub var max_nodes_per_pass: usize = 16 * 1024;
/// Passes an aborted Cx waits before verifying again.
pub var retry_after_passes: u32 = 60;

// Adaptive backoff. Verification pays for itself only through the cache reuse its trust unlocks
// in the paint pass. After each verified frame, Cx.render reports that frame's reuse
// (notePaintReuse: own payload hits + subtree payload splices + retained memo replayed nodes +
// promoted / legacy cache hits, i.e. what the paint did not re-record) against the nodes the pass
// compared. When reuse * backoff_ratio < compared nodes for backoff_streak verified frames in a
// row, the Cx stops verifying for backoff_passes frames (today's untrusted path for every hook,
// entered through endTrust like an abort) and then tries again. The measure is per Cx, not per
// hook: reuse is not attributed to hook subtrees.
// Streaming chat (S2): ~1,200 compared nodes, ~30 reused per frame -> backs off. S4 / S1 /
// overlays reuse about as many nodes as they compare (or more) -> keep verifying.
/// Reuse must reach 1 / backoff_ratio of the compared nodes.
pub var backoff_ratio: u32 = 10;
/// Low-benefit verified frames in a row before backing off.
pub var backoff_streak: u16 = 16;
/// Frames without verification after a backoff.
pub var backoff_passes: u32 = 240;
/// Tests: the next verifyFrame of every Cx backs off (cleared by it).
pub var force_backoff: bool = false;

// ---------------------------------------------------------------------------------------------
// Audit: every field of the structs the shadow copies, and every pointer inside them.

/// Policy of each pointer / slice reachable inside the copied structs (by "Type.field" path).
/// identity: compared by address (bytes of the holder); the pointee is not edited in place.
/// deep: the pointee is copied and compared (StyleExt). bytes / values: slice contents copied.
/// unverifiable: a non-null value makes the node unverifiable (marked dirty every frame).
const PointerPolicy = enum { identity, deep, bytes, values, unverifiable };
const pointer_policy = .{
    .{ "Style.ext", PointerPolicy.deep },
    // Layout-only GridConfig (no paint-pass read); an in-place edit shows as the rects it changes.
    .{ "StyleExt.grid", PointerPolicy.identity },
    .{ "GlassParams.group", PointerPolicy.unverifiable }, // shared glass group shapes
    .{ "TextProps.content", PointerPolicy.bytes },
    .{ "TextProps.spans", PointerPolicy.values },
    // Points into the compiled icon asset tables (svg_assets pickRep), which are constant.
    .{ "Rep.shapes", PointerPolicy.identity },
    .{ "NodeGeometries.path", PointerPolicy.unverifiable },
    .{ "NodeGeometries.custom_clip", PointerPolicy.unverifiable },
    .{ "NodeStroke.geometry", PointerPolicy.unverifiable },
    // Node-owned path paint shape (Node.setShapePath): replaced, never edited in place.
    .{ "NodeVector.shape", PointerPolicy.unverifiable },
    // storeTextLayout overwrites the pointee in place: when the World slot's revision moved, the
    // pointee is compared by value (TextLayoutCopy); a node without a World slot holding one is
    // unverifiable.
    .{ "LayoutArtifacts.text_layout", PointerPolicy.identity },
};

fn shortName(comptime T: type) []const u8 {
    const full = @typeName(T);
    const i = comptime std.mem.lastIndexOfScalar(u8, full, '.') orelse return full;
    return full[i + 1 ..];
}

fn policyOf(comptime path: []const u8) ?PointerPolicy {
    inline for (pointer_policy) |entry| {
        if (comptime std.mem.eql(u8, entry[0], path)) return entry[1];
    }
    return null;
}

/// Walks T; every pointer / slice must sit under a field listed in pointer_policy.
fn auditPointers(comptime T: type, comptime where: []const u8) void {
    @setEvalBranchQuota(200_000);
    switch (@typeInfo(T)) {
        .@"struct" => {
            inline for (reflection.fields(T)) |f| {
                const path = shortName(T) ++ "." ++ f.name;
                if (comptime policyOf(path) == null) auditPointers(f.type, path);
            }
        },
        .optional => |o| auditPointers(o.child, where),
        .array => |a| auditPointers(a.child, where),
        .@"union" => inline for (reflection.fields(T)) |f| auditPointers(f.type, where ++ "." ++ f.name),
        .pointer => @compileError("raw_shadow: unclassified pointer at " ++ where ++ " (" ++ @typeName(T) ++ "): add it to pointer_policy"),
        .@"fn" => @compileError("raw_shadow: unclassified function at " ++ where),
        else => {},
    }
}

fn expectFields(comptime T: type, comptime names: []const []const u8) void {
    @setEvalBranchQuota(200_000);
    const fs = reflection.fields(T);
    if (fs.len != names.len) @compileError("raw_shadow: " ++ @typeName(T) ++ " gained or lost a field: classify it (see module doc) and update the list");
    inline for (fs, names) |f, n| {
        if (!std.mem.eql(u8, f.name, n)) @compileError("raw_shadow: " ++ @typeName(T) ++ " field " ++ f.name ++ " is not in the audited list (expected " ++ n ++ ")");
    }
}

comptime {
    // Copied whole (bytes compared): every field is covered; the lists make a new field a
    // conscious decision (where does it live, does the paint pass read it?).
    expectFields(Style, &.{ "border", "padding", "direction", "justify", "align_items", "align_content", "gap", "width", "height", "flex", "flex_shrink", "translate_x", "translate_y", "overflow", "overflow_hidden", "margin", "position", "display", "cursor", "layout_isolation", "ext" });
    expectFields(StyleExt, &.{ "shadows", "shadow_count", "gradient", "outline", "corner_radius", "container_shape_radius", "scale_x", "scale_y", "motion_offset", "rotate", "transform_origin", "flex_basis", "align_self", "no_cross_stretch", "margin_auto_mask", "inset", "sticky_insets", "z_index", "tab_index", "aspect_ratio", "grid", "grid_placement", "min_width", "max_width", "min_height", "max_height", "flex_wrap", "hit_shape", "clip_shape", "hit_clip_shape", "shape", "hit_behavior", "hit_roles", "glass", "multi_gradient", "noise", "inset_shadow", "extra_inset_shadows", "extra_inset_count", "overflow_fade", "border_side_colors", "keep_rendering_when_transparent", "will_change_transform", "will_change_opacity", "composited_group", "content_warp", "blend_mode", "text_color", "text_font_size", "text_font_weight" });
    expectFields(PaintStateData, &.{ "background", "opacity" });
    expectFields(TextProps, &.{ "color_set", "font_size_set", "font_weight_set", "content", "color", "font_size", "font_weight", "font_family", "line_height", "selectable", "wrap", "overflow_wrap", "word_break", "max_lines", "baseline_ratio", "inline_buf", "inline_len", "use_symbols_font", "use_monospace_font", "use_italic_font", "font_smoothing", "strikethrough", "monospace_char_width", "owned", "text_overflow", "text_align", "fade_right", "spans", "spans_affect_layout", "spans_owned" });
    expectFields(IconProps, &.{ "icon_id", "rep", "tint", "tint_current_color" });
    expectFields(ImageProps, &.{ "texture_id", "tint", "tint_current_color" });
    expectFields(nlo.NodeLayoutOutput, &.{ "vector", "artifacts" });
    expectFields(nlo.NodeVector, &.{ "fill", "stroke", "shape" });
    expectFields(nlo.NodeGeometries, &.{ "path", "custom_clip" });
    expectFields(nlo.NodeStroke, &.{ "geometry", "color", "width", "line_join" });
    expectFields(nlo.LayoutArtifacts, &.{ "children_bbox", "text_layout" });
    expectFields(node_mod.NodeFlags, &.{ "out_of_viewport", "hit_test_visible", "text_stabilize_subtree", "manual_transform_animation_active", "manual_opacity_animation_active", "has_custom_draw_subtree", "has_text_subtree", "has_before_render_subtree", "disable_render_cache", "test_id_owned", "is_mounted", "inspectable", "inspect_pick_disabled", "before_render_hook_descendants_cache_safe", "before_render_hook_affects_self_only", "has_untrusted_before_render_subtree" });
    // Node: tag / style / children / frame_state (flags, sticky) / meta (custom hooks, hooks)
    // are read below; the rest is identity, tree links and lifetime bookkeeping.
    expectFields(Node, &.{ "id", "host_id", "tag", "style", "cursor_query", "cursor_query_context", "on_capture_lost", "element_id_raw", "world_id", "world_ref", "children", "parent", "deferred_disposal", "pending_free_cx", "freeing", "alive_sentinel", "frame_state", "meta", "behavior" });
    expectFields(node_mod.CustomHooks, &.{ "draw", "hit_test", "hit_proxy", "clip_meta" });
    expectFields(node_mod.NodeRuntime, &.{ "layout_mount_pending", "hidden", "sticky", "linger", "tick_quiet_epoch", "transitions", "commands" });
    // BoxStyle is where a new style property is declared: it must land in one of the stores
    // above (Style / StyleExt / paint state / content) or be classified here.
    expectFields(types.BoxStyle, &.{ "width", "height", "direction", "justify", "align_items", "align_content", "gap", "padding", "margin", "margin_spec", "flex", "flex_shrink", "flex_wrap", "blend_mode", "z_index", "inset", "gradient", "clip_shape", "glass", "multi_gradient", "composited_group", "content_warp", "grid_placement", "corner_radii", "inset_shadows", "outline", "flex_basis", "align_self", "no_cross_stretch", "sticky_insets", "tab_index", "aspect_ratio", "min_width", "max_width", "min_height", "max_height", "hit_shape", "shape", "hit_behavior", "hit_roles", "noise", "inset_shadow", "overflow_fade", "keep_rendering_when_transparent", "will_change_transform", "will_change_opacity", "position", "display", "overflow", "overflow_hidden", "layout_isolation", "background", "opacity", "cursor", "translate_x", "translate_y", "scale_x", "scale_y", "rotate", "transform_origin", "border", "border_color", "border_width", "border_overlay", "border_top_width", "border_right_width", "border_bottom_width", "border_left_width", "border_top_color", "border_right_color", "border_bottom_color", "border_left_color", "corner_radius", "shadow", "shadows", "text_color", "font_size", "font_weight", "icon_color" });

    auditPointers(Style, "Style");
    auditPointers(StyleExt, "StyleExt");
    auditPointers(PaintStateData, "PaintStateData");
    auditPointers(TextProps, "TextProps");
    auditPointers(TextSpan, "TextSpan");
    auditPointers(IconProps, "IconProps");
    auditPointers(ImageProps, "ImageProps");
    auditPointers(nlo.NodeLayoutOutput, "NodeLayoutOutput");
    auditPointers(node_mod.NodeFlags, "NodeFlags");
    auditPointers(node_mod.StickyOffset, "StickyOffset");
}

// ---------------------------------------------------------------------------------------------
// Per-Cx and per-node state

/// Per-Cx verification state (Cx.hook_verify).
pub const CxState = struct {
    /// Verification pass counter (one per Cx.render that ran the paint pass).
    seq: u32 = 0,
    /// Bumped by an aborted pass: every shadow of this Cx is stale.
    generation: u32 = 0,
    /// Pass seq before which a hook that aborted is not retried.
    retry_after: u32 = 0,
    /// The last pass trusted its hooks (see endTrust).
    trusted_last_pass: bool = false,
    /// Consecutive verified frames whose paint reused too little for what the pass compared
    /// (notePaintReuse).
    low_benefit_streak: u16 = 0,
    /// The next frame starts a backoff (notePaintReuse, force_backoff).
    backoff_pending: bool = false,
    /// The current retry window is a backoff (counters only).
    in_backoff: bool = false,
};

/// Per-node verification result of the current pass (NodeCaches.hook_verify, defined in node.zig
/// to keep the import one-way at layout time).
pub const NodeState = node_mod.HookVerifyState;

/// The pass whose results the render engine reads: the Cx (token = its World id) and its seq.
/// Set by Cx.render around its own paint pass and restored afterwards, so a node's state only
/// counts for the Cx that wrote it, during that Cx's paint (seq 0: nothing verified).
pub const Current = struct {
    seq: u32 = 0,
    token: u16 = 0,
    /// Verification is on but this frame has no completed pass (aborted, or skipped in the retry
    /// window after an abort): seq is 0 (nothing trusted), formerRootUnverified still applies.
    unverified: bool = false,
};
pub var current: Current = .{};

/// Node.beforeRenderHooksCacheTrusted, or covered by this frame's verification. A node whose
/// undeclared hook ran this tick or was an outermost hook root last pass and is gone (or now
/// declared trusted) is not trusted until a completed pass has walked it (formerRootUnverified).
pub fn hookTrustedThisFrame(node: *const Node) bool {
    if (node.beforeRenderHooksCacheTrusted()) return !formerRootUnverified(node);
    const st = node.meta.per_frame.caches.hook_verify;
    return current.seq != 0 and st.seq == current.seq and st.token == current.token and st.trusted;
}

/// An untrusted hook owns this node's subtree this frame: it has one that this frame's
/// verification did not cover, or one just went away unverified (formerRootUnverified).
pub fn untrustedHookOwnerThisFrame(node: *const Node) bool {
    return !hookTrustedThisFrame(node);
}

/// The node's undeclared hook ran this tick (ran_untrusted) or it was an outermost hook root, and
/// no completed pass of this frame walked it since (the pass aborted before or on it): its last
/// raw writes are unmarked, so its subtree keeps today's path for this frame, like a hook node's
/// (visitChain walks it again in the next completed pass). Verification off: today's path
/// exactly (nothing here).
pub fn formerRootUnverified(node: *const Node) bool {
    // A node that still has an undeclared hook is handled as a hook node (hookTrustedThisFrame,
    // beforeRenderHookTaintsSubtree with its self-only / custom-draw exceptions); this only
    // covers a hook that is gone or now declared trusted.
    if (node.hasBeforeRenderHooks() and !node.beforeRenderHooksCacheTrusted()) return false;
    if (current.seq == 0 and !current.unverified) return false;
    const st = node.meta.per_frame.caches.hook_verify;
    if (!(st.root or st.ran_untrusted)) return false;
    return !(st.seq == current.seq and st.token == current.token and st.trusted);
}

/// has_untrusted_before_render_subtree, minus what this frame's verification covered.
pub fn untrustedHookSubtreeThisFrame(node: *const Node) bool {
    if (!node.frame_state.state_bits.flags.has_untrusted_before_render_subtree) return false;
    const st = node.meta.per_frame.caches.hook_verify;
    return !(current.seq != 0 and st.seq == current.seq and st.token == current.token and st.chain_ok);
}

// ---------------------------------------------------------------------------------------------
// Shadow

pub const Shadow = struct {
    allocator: Allocator,
    seq: u32 = 0,
    generation: u32 = 0,
    tag: types.ElementTag,
    style: Style,
    /// Copy of the StyleExt pointee, valid when has_ext (inline: one allocation per node).
    ext: StyleExt = .{},
    has_ext: bool = false,
    paint: PaintStateData,
    rect: ComputedRect,
    layout: nlo.NodeLayoutOutput,
    has_layout: bool,
    text: ?TextProps,
    text_bytes: std.ArrayList(u8) = .empty,
    spans: std.ArrayList(TextSpan) = .empty,
    icon: ?IconProps,
    image: ?ImageProps,
    children: std.ArrayList(*Node) = .empty,
    flags: u16,
    /// World layout-output slot revision (text layout stores / clears, see pointer_policy) and the
    /// text layout's value at that revision.
    layout_revision: u64 = 0,
    text_layout: TextLayoutCopy = .{},
    sticky: node_mod.StickyOffset,
    draw: usize,
    clip_provider: usize,
    before_render: node_mod.BeforeRenderHooks,

    fn deinit(self: *Shadow) void {
        const a = self.allocator;
        self.text_bytes.deinit(a);
        self.spans.deinit(a);
        self.children.deinit(a);
        self.text_layout.lines.deinit(a);
        a.destroy(self);
    }
};

pub fn shadowOf(node: *const Node) ?*Shadow {
    const p = node.meta.per_frame.caches.raw_shadow orelse return null;
    return @ptrCast(@alignCast(p));
}

/// Frees the node's shadow (node destruction; also safe at any time: the next pass then treats
/// the node as changed).
pub fn dropShadow(node: *Node) void {
    if (shadowOf(node)) |s| s.deinit();
    node.meta.per_frame.caches.raw_shadow = null;
}

/// Every byte of `a` and `b` equal. Up to 256 bytes as one vector compare (fixed size, no call to
/// the generic std.mem.eqlBytes loop), larger through std.mem.eql: the same predicate either way.
inline fn bytesEql(comptime T: type, a: *const T, b: *const T) bool {
    const n = @sizeOf(T);
    if (n == 0) return true;
    if (n > 256) return std.mem.eql(u8, std.mem.asBytes(a), std.mem.asBytes(b));
    const x: @Vector(n, u8) = std.mem.asBytes(a).*;
    const y: @Vector(n, u8) = std.mem.asBytes(b).*;
    return @reduce(.And, x == y);
}

/// The machine word the whole-struct compares read T in: 64-bit where T is 8-aligned (every
/// native target), 32-bit on wasm32 (4-byte pointers leave Style / StyleExt 4-aligned).
fn Word(comptime T: type) type {
    if (@alignOf(T) >= 8 and @sizeOf(T) % 8 == 0) return u64;
    std.debug.assert(@alignOf(T) >= 4 and @sizeOf(T) % 4 == 0);
    return u32;
}

/// Whole-struct compare as machine words (Word), the bytes of `skip` fields masked out. Like
/// bytesEql (padding can only cause a false difference), in a few vector instructions.
fn wordsEql(comptime T: type, a: *const T, b: *const T, comptime skip: []const []const u8) bool {
    const W = Word(T);
    const n = @sizeOf(T) / @sizeOf(W);
    const wa: *const [n]W = @ptrCast(@alignCast(a));
    const wb: *const [n]W = @ptrCast(@alignCast(b));
    if (skip.len == 0) {
        var acc: W = 0;
        for (wa, wb) |x, y| acc |= x ^ y;
        return acc == 0;
    }
    const mask = comptime blk: {
        var bytes: [@sizeOf(T)]u8 = @splat(0xff);
        for (skip) |name| {
            const off = @offsetOf(T, name);
            for (off..off + @sizeOf(@FieldType(T, name))) |i| bytes[i] = 0;
        }
        break :blk @as([n]W, @bitCast(bytes));
    };
    var acc: W = 0;
    for (wa, wb, &mask) |x, y, m| acc |= (x ^ y) & m;
    return acc == 0;
}

/// Byte mask of T with the bytes of `fields` cleared, as words (Word).
fn wordMask(comptime T: type, comptime fields: []const []const u8) [@sizeOf(T) / @sizeOf(Word(T))]Word(T) {
    comptime {
        @setEvalBranchQuota(200_000);
        var bytes: [@sizeOf(T)]u8 = @splat(0xff);
        for (fields) |name| {
            const off = @offsetOf(T, name);
            for (off..off + @sizeOf(@FieldType(T, name))) |i| bytes[i] = 0;
        }
        return @bitCast(bytes);
    }
}

/// How extDiff reads a word of StyleExt.
const WordKind = enum { skip, full, partial };
const WordRun = struct { start: usize, end: usize, kind: WordKind };

/// Maximal runs of words of the same kind: `skip` (no compared byte), `full` (every byte compared,
/// none composite), `partial` (the masks apply).
fn wordRuns(comptime W: type, comptime n: usize, comptime all: [n]W, comptime nc: [n]W) []const WordRun {
    comptime {
        @setEvalBranchQuota(200_000);
        var out: []const WordRun = &.{};
        var i: usize = 0;
        while (i < n) {
            const kind = kindOf(W, all[i], nc[i]);
            const start = i;
            while (i < n and kindOf(W, all[i], nc[i]) == kind) i += 1;
            if (kind != .skip) out = out ++ .{WordRun{ .start = start, .end = i, .kind = kind }};
        }
        return out;
    }
}

fn kindOf(comptime W: type, comptime all: W, comptime nc: W) WordKind {
    if (all == 0) return .skip;
    if (all == ~@as(W, 0) and nc == ~@as(W, 0)) return .full;
    return .partial;
}

/// Result of extDiff.
const ExtDiff = struct {
    /// Some compared StyleExt byte differs.
    any: bool,
    /// Some byte outside composite_ext_fields differs.
    non_composite: bool,
};

/// StyleExt optionals compared as values (null state, then the payload when set) rather than by
/// all their bytes: the large ones (GlassParams 512 bytes, MultiGradient 152), null on almost
/// every node, whose payload is over half of StyleExt.
const ext_value_optionals: []const []const u8 = blk: {
    var names: []const []const u8 = &.{};
    for (reflection.fields(StyleExt)) |f| {
        if (@typeInfo(f.type) == .optional and @sizeOf(f.type) >= 64) names = names ++ .{f.name};
    }
    break :blk names;
};

/// Compares two StyleExt blocks in one pass, the verdicts of the former
/// `wordsEql(StyleExt, a, b, &.{})` (any) and `wordsEql(StyleExt, a, b, &composite_ext_fields)`
/// (non_composite) at once: every word is loaded once, both masks applied to its difference.
/// Words that only hold bytes of ext_value_optionals are not loaded; those optionals are compared
/// by optEql (null state, then the payload bytes when set), none of them is composite.
///
/// Same verdicts except when the only bytes that differ are bytes of such an optional no reader
/// can see: its payload while it is null on both sides, or its padding after the null flag. A
/// null optional's payload cannot be read (`if (x) |v|`, `x.?` never reach it), padding is never
/// read, so no reader of StyleExt, the paint pass included, sees that difference: the rule
/// fieldsEql / optEql already apply ("a null optional ignores its payload"; padding "may only
/// cause a false difference").
///
/// Not inlined: with both masked compares inlined into compare(), LLVM kept all 150 words of each
/// side live across them and spilled them to the stack (most of walk's samples).
noinline fn extDiff(a: *const StyleExt, b: *const StyleExt) ExtDiff {
    const W = Word(StyleExt);
    const n = @sizeOf(StyleExt) / @sizeOf(W);
    const all_mask = comptime wordMask(StyleExt, ext_value_optionals);
    const nc_mask = comptime wordMask(StyleExt, ext_value_optionals ++ composite_ext_fields);
    const runs = comptime wordRuns(W, n, all_mask, nc_mask);
    const wa: *const [n]W = @ptrCast(@alignCast(a));
    const wb: *const [n]W = @ptrCast(@alignCast(b));
    // Full words: one accumulator, in 4-word vectors.
    const V = @Vector(4, W);
    var vacc: V = @splat(0);
    var full: W = 0;
    var any: W = 0;
    var nc: W = 0;
    inline for (runs) |r| switch (r.kind) {
        .skip => unreachable,
        .full => {
            comptime var i = r.start;
            inline while (i + 4 <= r.end) : (i += 4) {
                const x: V = wa[i..][0..4].*;
                const y: V = wb[i..][0..4].*;
                vacc |= x ^ y;
            }
            inline while (i < r.end) : (i += 1) full |= wa[i] ^ wb[i];
        },
        .partial => inline for (r.start..r.end) |i| {
            const d = wa[i] ^ wb[i];
            any |= d & all_mask[i];
            nc |= d & nc_mask[i];
        },
    };
    full |= @reduce(.Or, vacc);
    any |= full;
    nc |= full;
    var out: ExtDiff = .{ .any = any != 0, .non_composite = nc != 0 };
    if (out.non_composite) return out;
    inline for (ext_value_optionals) |name| {
        comptime std.debug.assert(!inList(name, &composite_ext_fields));
        if (!optEql(@typeInfo(@FieldType(StyleExt, name)).optional.child, &@field(a, name), &@field(b, name))) {
            out = .{ .any = true, .non_composite = true };
            return out;
        }
    }
    return out;
}

fn inList(comptime name: []const u8, comptime list: []const []const u8) bool {
    inline for (list) |n| if (comptime std.mem.eql(u8, n, name)) return true;
    return false;
}

/// Field by field, each field by its bytes, except that a null optional ignores its payload (the
/// paint pass cannot read it) and `skip` fields are left out. Every byte that can matter is
/// compared; padding may only cause a false difference (a needless re-record), never hide one.
inline fn fieldsEql(comptime T: type, a: *const T, b: *const T, comptime skip: []const []const u8) bool {
    @setEvalBranchQuota(100_000);
    inline for (reflection.fields(T)) |f| {
        if (comptime inList(f.name, skip)) continue;
        const fa = &@field(a, f.name);
        const fb = &@field(b, f.name);
        switch (@typeInfo(f.type)) {
            .optional => {
                if ((fa.* == null) != (fb.* == null)) return false;
                if (fa.*) |*va| if (!bytesEql(@TypeOf(va.*), va, &fb.*.?)) return false;
            },
            else => if (!bytesEql(f.type, fa, fb)) return false,
        }
    }
    return true;
}

/// Same as RenderContext.rectFromWorld.
fn worldRect(world: *world_mod.World, node: *const Node) ComputedRect {
    if (node.element_id_raw == 0xFFFFFFFF) return node.rectFromWorldOrFallback();
    const eid = world_mod.ElementId.fromRaw(node.element_id_raw);
    if (world.layout.rect(eid)) |r| return ComputedRect.init(r.x, r.y, r.width, r.height);
    return node.rectFromWorldOrFallback();
}

fn paintOf(node: *const Node) PaintStateData {
    return .{ .background = node.getBackground(), .opacity = node.getOpacity() };
}

/// The World-table part of a node's render input, read once (the getters the paint pass uses,
/// without repeating the element lookup per field). The content fields point into the World's
/// content slot when the node has one (no copy), else into `own`.
const Raw = struct {
    text: *const ?TextProps,
    icon: *const ?IconProps,
    image: *const ?ImageProps,
    paint: PaintStateData,
    rect: ComputedRect,
    layout: ?*const nlo.NodeLayoutOutput,
    /// The World layout-output slot's revision (0 without a World slot), read with the rest. Only
    /// storeTextLayout / clearTextLayout move it, never the dirty marking verifyNode does between
    /// gather and refresh / the shadow update.
    revision: u64,
    own: ContentCopy = .{},

    const ContentCopy = struct { text: ?TextProps = null, icon: ?IconProps = null, image: ?ImageProps = null };
    const none: ContentCopy = .{};
};

fn gather(raw: *Raw, world: *world_mod.World, node: *const Node) void {
    if (node.world_ref) |w| if (node.element_id_raw != 0xFFFFFFFF) {
        const eid = world_mod.ElementId.fromRaw(node.element_id_raw);
        // Same reads as paint_content_accessor (readText / readIcon / readImage go no further
        // than the World's content table when the node has one; paint state falls back).
        raw.paint = w.paint_state.get(eid) orelse paintOf(node);
        raw.rect = worldRect(world, node);
        raw.layout = w.layout_output.getConstPtr(eid);
        raw.revision = w.layout_output.revisionOf(eid) orelse 0;
        if (w.content.getPtr(eid)) |c| {
            raw.text = &c.text;
            raw.icon = &c.icon;
            raw.image = &c.image;
        } else {
            raw.text = &Raw.none.text;
            raw.icon = &Raw.none.icon;
            raw.image = &Raw.none.image;
        }
        return;
    };
    raw.own = .{ .text = node.getTextRaw(), .icon = node.getIcon(), .image = node.getImage() };
    raw.text = &raw.own.text;
    raw.icon = &raw.own.icon;
    raw.image = &raw.own.image;
    raw.paint = paintOf(node);
    raw.rect = worldRect(world, node);
    raw.layout = node.layoutOutput();
    raw.revision = 0;
}

/// Optionals by value, a null one ignoring its payload bytes.
inline fn optEql(comptime T: type, a: *const ?T, b: *const ?T) bool {
    if ((a.* == null) != (b.* == null)) return false;
    if (a.*) |*x| return bytesEql(T, x, &b.*.?);
    return true;
}

comptime {
    expectFields(@import("../content_table.zig").ContentData, &.{ "text", "image", "icon" });
}

fn clipProviderOf(node: *const Node) usize {
    return if (node.meta.per_frame.custom_hooks.clip_meta.provider) |p| @intFromPtr(p) else 0;
}

fn drawOf(node: *const Node) usize {
    return if (node.meta.per_frame.custom_hooks.draw) |d| @intFromPtr(d.callback) ^ (if (d.context) |c| @intFromPtr(c) *% 31 else 0) else 0;
}

/// NodeFlags without out_of_viewport: the tick rewrites it for nodes crossing the viewport and the
/// paint pass never reads it (only tick-side hooks do), so it is not render input.
fn flagBits(node: *const Node) u16 {
    var f = node.frame_state.state_bits.flags;
    f.out_of_viewport = false;
    return @bitCast(f);
}

const TextLayout = @import("../text_layout.zig").TextLayout;
const LineInfo = @import("../text_layout.zig").LineInfo;

/// A TextLayout by value: its used lines plus every other field (cache keys included).
const TextLayoutCopy = struct {
    present: bool = false,
    lines: std.ArrayList(LineInfo) = .empty,
    head: Head = undefined,

    const Head = struct {
        line_count: u32,
        total_height: f32,
        max_line_width: f32,
        lines_truncated: bool,
        cached_content_ptr: usize,
        cached_content_len: usize,
        cached_content_hash: u64,
        cached_available_width: f32,
        cached_font_weight: u16,
        cached_font_size: f32,
        cached_line_height: f32,
        cached_measure_generation: u32,
        cached_measure_ctx: usize,
        cached_measure_ctx_fn: usize,
        cached_shape_fn: usize,
        cached_use_italic: bool,
        cached_use_monospace: bool,
        cached_wrap: types.TextWrap,
        cached_max_lines: u16,
        cached_spans_hash: u64,
    };

    fn headOf(t: *const TextLayout) Head {
        return .{
            .line_count = t.line_count,
            .total_height = t.total_height,
            .max_line_width = t.max_line_width,
            .lines_truncated = t.lines_truncated,
            .cached_content_ptr = @intFromPtr(t.cached_content_ptr),
            .cached_content_len = t.cached_content_len,
            .cached_content_hash = t.cached_content_hash,
            .cached_available_width = t.cached_available_width,
            .cached_font_weight = t.cached_font_weight,
            .cached_font_size = t.cached_font_size,
            .cached_line_height = t.cached_line_height,
            .cached_measure_generation = t.cached_measure_generation,
            .cached_measure_ctx = if (t.cached_measure_ctx) |c| @intFromPtr(c) else 0,
            .cached_measure_ctx_fn = if (t.cached_measure_ctx_fn) |f| @intFromPtr(f) else 0,
            .cached_shape_fn = if (t.cached_shape_fn) |f| @intFromPtr(f) else 0,
            .cached_use_italic = t.cached_use_italic,
            .cached_use_monospace = t.cached_use_monospace,
            .cached_wrap = t.cached_wrap,
            .cached_max_lines = t.cached_max_lines,
            .cached_spans_hash = t.cached_spans_hash,
        };
    }

    fn usedLines(t: *const TextLayout) []const LineInfo {
        return t.lines();
    }

    fn eql(self: *const TextLayoutCopy, t: ?*const TextLayout) bool {
        const x = t orelse return !self.present;
        if (!self.present) return false;
        const h = headOf(x);
        return fieldsEql(Head, &h, &self.head, &.{}) and
            std.mem.eql(u8, std.mem.sliceAsBytes(usedLines(x)), std.mem.sliceAsBytes(self.lines.items));
    }

    fn set(self: *TextLayoutCopy, a: Allocator, t: ?*const TextLayout) bool {
        self.lines.clearRetainingCapacity();
        const x = t orelse {
            self.present = false;
            return true;
        };
        self.present = true;
        self.head = headOf(x);
        self.lines.appendSlice(a, usedLines(x)) catch return false;
        return true;
    }
};

comptime {
    // TextLayoutCopy names every field it reads.
    expectFields(TextLayout, &.{ "inline_lines", "spill_lines", "line_count", "total_height", "max_line_width", "lines_truncated", "cached_content_ptr", "cached_content_len", "cached_content_hash", "cached_available_width", "cached_font_weight", "cached_font_size", "cached_line_height", "cached_measure_generation", "cached_measure_ctx", "cached_measure_ctx_fn", "cached_shape_fn", "cached_use_italic", "cached_use_monospace", "cached_wrap", "cached_max_lines", "cached_spans_hash" });
}

/// The node's render input cannot be fully held by a shadow (see module doc): it is marked dirty
/// every frame; the rest of its state is still compared (inherited text style).
fn unverifiable(node: *const Node, raw: *const Raw) bool {
    const layout = raw.layout;
    if (node.meta.per_frame.custom_hooks.draw != null) return true;
    if (node.meta.per_frame.custom_hooks.clip_meta.provider != null) return true;
    // A text layout outside a World slot has no revision to compare (stored in place).
    if (layout) |lo| if (lo.artifacts.text_layout != null and (node.world_ref == null or node.element_id_raw == 0xFFFFFFFF)) return true;
    if (layout) |lo| {
        if (lo.vector.fill.path != null or lo.vector.fill.custom_clip != null or lo.vector.stroke.geometry != null or lo.vector.shape != null) return true;
    }
    if (node.style.ext) |e| if (e.glass) |g| if (g.group != null) return true;
    if (raw.text.*) |*t| if (t.content.len > max_text_bytes or t.spans.len > max_spans) return true;
    return false;
}

fn layoutEql(a: *const nlo.NodeLayoutOutput, b: *const nlo.NodeLayoutOutput) bool {
    return fieldsEql(nlo.NodeGeometries, &a.vector.fill, &b.vector.fill, &.{}) and
        fieldsEql(nlo.NodeStroke, &a.vector.stroke, &b.vector.stroke, &.{}) and
        a.vector.shape == b.vector.shape and
        fieldsEql(nlo.LayoutArtifacts, &a.artifacts, &b.artifacts, &.{});
}

fn hooksEql(a: *const node_mod.BeforeRenderHooks, b: *const node_mod.BeforeRenderHooks) bool {
    if (a.main != b.main or a.count != b.count or a.self_only_mask != b.self_only_mask or a.trusted_mask != b.trusted_mask) return false;
    const n = @min(a.count, a.hooks.len);
    return std.mem.eql(?*const fn (*Node) void, a.hooks[0..n], b.hooks[0..n]);
}

comptime {
    // layoutEql / hooksEql name the fields they read.
    expectFields(node_mod.BeforeRenderHooks, &.{ "main", "count", "hooks", "self_only_mask", "trusted_mask" });
}

/// Result of comparing a node with its shadow.
const Diff = struct {
    /// Anything but translate differs (or there is no fresh shadow).
    own: bool = false,
    /// Only translate_x / translate_y differ.
    translate: bool = false,
    /// Composite-only properties differ (StyleExt scale_x / scale_y / rotate, paint opacity): the
    /// ones the API writers mark with markCompositePropDirty (Node.setOpacity, the style
    /// transition props), never a re-record. Only its **render** part is applied
    /// (node_dirty.markUnmarkedTranslation: composite bits, own render cache), so a promoted /
    /// legacy surface the node owns stays valid (Popover scale_fade: its main hook animates scale
    /// and opacity raw). The interaction part (markInteractionDirty, hit geometry, hostDirty) is
    /// not: a raw scale / rotate leaves hit-testing on the old geometry, as any raw write does
    /// today. Hit state is outside this verification by design (module doc); it restores render
    /// output only.
    /// StyleExt.motion_offset belongs here too: the transient part of the translate (overlay
    /// enter / exit slides), read by the retained build (scene_runtime content_motion: the rest
    /// origin a surface anchors its pixel grid to) and the raster-policy check
    /// (animation_checks.hasMovingTransformAnimation, whose flips the paint pass handles without
    /// dirty bits), never recorded into content. Its writers mark composite only:
    /// TransitionController (markCompositeAnimFrameDirty) and Popover's anchored slide
    /// (setPopoverTranslate, markCompositePropDirty with the translate it is part of).
    composite: bool = false,
    /// StyleExt text_color / text_font_size / text_font_weight differ (descendants read them).
    inherited: bool = false,
};

fn inheritedDiffers(a: ?*const StyleExt, b: ?*const StyleExt) bool {
    const ac: ?types.Color = if (a) |e| e.text_color else null;
    const bc: ?types.Color = if (b) |e| e.text_color else null;
    const as: ?f32 = if (a) |e| e.text_font_size else null;
    const bs: ?f32 = if (b) |e| e.text_font_size else null;
    const aw: ?u16 = if (a) |e| e.text_font_weight else null;
    const bw: ?u16 = if (b) |e| e.text_font_weight else null;
    return !bytesEql(?types.Color, &ac, &bc) or !bytesEql(?f32, &as, &bs) or !bytesEql(?u16, &aw, &bw);
}

/// StyleExt fields a composite-only diff may touch (Diff.composite).
const composite_ext_fields = [_][]const u8{ "scale_x", "scale_y", "rotate", "motion_offset" };

fn compare(node: *const Node, s: *const Shadow, raw: *const Raw) Diff {
    const layout = raw.layout;
    var d: Diff = .{};
    // Style without translate, then translate.
    if (!wordsEql(Style, &node.style, &s.style, &.{ "translate_x", "translate_y" })) d.own = true;
    if (@as(u32, @bitCast(node.style.translate_x)) != @as(u32, @bitCast(s.style.translate_x)) or
        @as(u32, @bitCast(node.style.translate_y)) != @as(u32, @bitCast(s.style.translate_y))) d.translate = true;
    const se: ?*const StyleExt = if (s.has_ext) &s.ext else null;
    if (node.style.ext) |e| {
        if (se) |x| {
            // Unmasked first (the common equal case), then classify.
            const ed = extDiff(e, x);
            if (ed.non_composite) {
                d.own = true;
                if (inheritedDiffers(e, x)) d.inherited = true;
            } else if (ed.any) d.composite = true;
        } else {
            d.own = true;
            d.inherited = inheritedDiffers(e, null);
        }
    } else if (se) |x| {
        d.own = true;
        d.inherited = inheritedDiffers(null, x);
    }
    if (d.own) return d;
    if (node.tag != s.tag) d.own = true;
    if (!bytesEql(PaintStateData, &raw.paint, &s.paint)) {
        if (!bytesEql(types.Color, &raw.paint.background, &s.paint.background)) d.own = true;
        if (@as(u32, @bitCast(raw.paint.opacity)) != @as(u32, @bitCast(s.paint.opacity))) d.composite = true;
    }
    if (!bytesEql(ComputedRect, &raw.rect, &s.rect)) d.own = true;
    if ((layout != null) != s.has_layout) d.own = true else if (layout) |lo| if (!layoutEql(lo, &s.layout)) {
        d.own = true;
    };
    if (d.own) return d;
    if ((raw.text.* == null) != (s.text == null)) return .{ .own = true, .translate = d.translate };
    if (raw.text.*) |*t| {
        if (!bytesEql(TextProps, t, &s.text.?)) return .{ .own = true, .translate = d.translate };
        if (!std.mem.eql(u8, t.content, s.text_bytes.items)) return .{ .own = true, .translate = d.translate };
        if (t.spans.len != s.spans.items.len or !std.mem.eql(u8, std.mem.sliceAsBytes(t.spans), std.mem.sliceAsBytes(s.spans.items))) return .{ .own = true, .translate = d.translate };
    }
    if (!optEql(IconProps, raw.icon, &s.icon)) d.own = true;
    if (!optEql(ImageProps, raw.image, &s.image)) d.own = true;
    if (!std.mem.eql(*Node, node.children.items, s.children.items)) d.own = true;
    if (flagBits(node) != s.flags) d.own = true;
    // Text layout: by value whenever the slot's revision moved (a relayout that stored the same
    // layout is no change).
    if (s.layout_revision != raw.revision) {
        const tl: ?*const TextLayout = if (layout) |lo| lo.artifacts.text_layout else null;
        if (!s.text_layout.eql(tl)) d.own = true;
    }
    if (!bytesEql(node_mod.StickyOffset, &node.frame_state.frame_local.runtime.sticky, &s.sticky)) d.own = true;
    if (drawOf(node) != s.draw or clipProviderOf(node) != s.clip_provider) d.own = true;
    if (!hooksEql(&node.meta.per_frame.hooks.before_render, &s.before_render)) d.own = true;
    return d;
}

/// Copies the node's current raw state into its shadow (allocating it). False on OOM.
fn refresh(node: *Node, allocator: Allocator, raw: *const Raw, seq: u32, generation: u32) bool {
    const text = raw.text.*;
    const layout = raw.layout;
    const s: *Shadow = shadowOf(node) orelse blk: {
        const fresh = allocator.create(Shadow) catch return false;
        fresh.* = .{
            .allocator = allocator,
            .tag = node.tag,
            .style = node.style,
            .paint = undefined,
            .rect = undefined,
            .layout = .{},
            .has_layout = false,
            .text = null,
            .icon = null,
            .image = null,
            .flags = 0,
            .sticky = .{},
            .draw = 0,
            .clip_provider = 0,
            .before_render = .{},
        };
        node.meta.per_frame.caches.raw_shadow = @ptrCast(fresh);
        break :blk fresh;
    };
    const a = s.allocator;
    s.tag = node.tag;
    s.style = node.style;
    s.has_ext = node.style.ext != null;
    if (node.style.ext) |e| s.ext = e.*;
    s.paint = raw.paint;
    s.rect = raw.rect;
    s.has_layout = layout != null;
    s.layout = if (layout) |lo| lo.* else .{};
    s.text = text;
    s.text_bytes.clearRetainingCapacity();
    s.spans.clearRetainingCapacity();
    if (text) |t| if (t.content.len <= max_text_bytes and t.spans.len <= max_spans) {
        s.text_bytes.appendSlice(a, t.content) catch {
            dropShadow(node);
            return false;
        };
        s.spans.appendSlice(a, t.spans) catch {
            dropShadow(node);
            return false;
        };
    };
    s.icon = raw.icon.*;
    s.image = raw.image.*;
    s.children.clearRetainingCapacity();
    s.children.appendSlice(a, node.children.items) catch {
        dropShadow(node);
        return false;
    };
    s.flags = flagBits(node);
    s.layout_revision = raw.revision;
    if (!s.text_layout.set(a, if (layout) |lo| lo.artifacts.text_layout else null)) {
        dropShadow(node);
        return false;
    }
    s.sticky = node.frame_state.frame_local.runtime.sticky;
    s.draw = drawOf(node);
    s.clip_provider = clipProviderOf(node);
    s.before_render = node.meta.per_frame.hooks.before_render;
    s.seq = seq;
    s.generation = generation;
    return true;
}

// ---------------------------------------------------------------------------------------------
// Frame pass

pub const Counters = struct {
    nodes: u32 = 0,
    diffs: u32 = 0,
    unverifiable: u32 = 0,
    skipped_cap: u32 = 0,
    verified_hooks: u32 = 0,
    /// Frames skipped by the adaptive backoff (a subset of skipped_cap).
    skipped_backoff: u32 = 0,
};

var disabled_cache: ?bool = null;
/// Test / bench override of ZENIT_DISABLE_HOOK_VERIFY (null: read the environment once).
pub var disabled_override: ?bool = null;

pub fn disabled() bool {
    if (disabled_override) |v| return v;
    return disabled_cache orelse blk: {
        const v = @import("zenit_environment").flag("ZENIT_DISABLE_HOOK_VERIFY");
        disabled_cache = v;
        break :blk v;
    };
}

const Pass = struct {
    world: *world_mod.World,
    allocator: Allocator,
    state: *CxState,
    seq: u32,
    counters: Counters = .{},
    token: u16,
    budget: usize,
    aborted: bool = false,
};

pub const FrameResult = struct { counters: Counters = .{}, current: Current = .{} };

/// Verifies every undeclared hook subtree under `root` (see module doc). Call once per frame right
/// before the paint pass and install the returned `current` for it (Cx.render saves and restores
/// the previous value). `token` identifies the Cx (its World id).
pub fn verifyFrame(state: *CxState, token: u16, world: *world_mod.World, allocator: Allocator, root: *Node) FrameResult {
    var out: FrameResult = .{};
    const has_hooks = root.frame_state.state_bits.flags.has_untrusted_before_render_subtree;
    if (disabled() or !has_hooks) {
        endTrust(state, root);
        return out;
    }
    state.seq +%= 1;
    if (state.seq == 0) state.seq = 1;
    var pass: Pass = .{ .world = world, .allocator = allocator, .state = state, .seq = state.seq, .token = token, .budget = max_nodes_per_pass };
    if (state.backoff_pending or force_backoff) {
        // Same transition as an abort: nothing trusted from this frame on, caches recorded under
        // the last pass's trust dropped (endTrust below), shadows stale (generation).
        force_backoff = false;
        state.backoff_pending = false;
        state.low_benefit_streak = 0;
        state.generation +%= 1;
        state.retry_after = state.seq +% @max(backoff_passes, 1);
        state.in_backoff = true;
    }
    if (state.retry_after != 0 and seqBefore(state.seq, state.retry_after)) {
        out.counters.skipped_cap += 1;
        if (state.in_backoff) out.counters.skipped_backoff += 1;
        endTrust(state, root);
        out.current = .{ .token = token, .unverified = true };
        return out;
    }
    state.in_backoff = false;
    _ = visitChain(&pass, root);
    out.counters = pass.counters;
    if (pass.aborted) {
        // Nothing is trusted this frame (today's path for every hook), and the shadows this pass
        // refreshed are not followed by a trusted paint: none of them is fresh any more.
        state.generation +%= 1;
        state.retry_after = state.seq +% retry_after_passes;
        out.counters.skipped_cap += 1;
        endTrust(state, root);
        out.current = .{ .token = token, .unverified = true };
        return out;
    }
    state.trusted_last_pass = true;
    out.current = .{ .seq = state.seq, .token = token };
    return out;
}

/// After the paint of a verified frame (result.current.seq != 0): `reused` cache replays against
/// `compared` nodes (see backoff_ratio).
pub fn notePaintReuse(state: *CxState, compared: u32, reused: u64) void {
    if (compared == 0) return;
    if (reused * backoff_ratio >= compared) {
        state.low_benefit_streak = 0;
        return;
    }
    state.low_benefit_streak +|= 1;
    if (state.low_benefit_streak >= backoff_streak) state.backoff_pending = true;
}

/// This frame trusts no hook of the Cx (disabled, skipped, aborted). If the last pass trusted
/// some, caches recorded under that trust inside hook subtrees are dropped now: today's path does
/// not expect them (the paint pass re-records hook-owned subtrees, but promoted / legacy overflow
/// caches and memos inside them would otherwise replay what was recorded while verified).
fn endTrust(state: *CxState, root: *Node) void {
    if (!state.trusted_last_pass) return;
    state.trusted_last_pass = false;
    dropAllHookCaches(root);
}

fn dropAllHookCaches(node: *Node) void {
    if (!node.frame_state.state_bits.flags.has_untrusted_before_render_subtree) return;
    const st = node.meta.per_frame.caches.hook_verify;
    if ((node.hasBeforeRenderHooks() and !node.beforeRenderHooksCacheTrusted()) or st.root or st.ran_untrusted) {
        dropHookCaches(node);
        return;
    }
    for (node.children.items) |child| dropAllHookCaches(child);
}

/// A hook node goes from verified (trusted last pass) to untrusted: every cross-frame cache inside
/// its subtree, and every memo / subtree payload of an ancestor (they contain it), is dropped.
pub fn dropHookCaches(node: *Node) void {
    dropSubtreeCaches(node);
    var p = node.parent;
    while (p) |a| : (p = a.parent) {
        @import("retained_memo.zig").dropMemo(a);
        node_render_cache.invalidateSubtreePayloadCache(a);
    }
}

/// A node leaves its parent (node_tree removeChildRetainedInternal, used by every removal and
/// reparent, and replaceChildOrder for omitted members: the only places that unlink a Node).
/// Unsupported: a hook that edits `parent` / `children` directly, bypassing node_tree (World
/// links, dirty bits and hosts would be inconsistent as well); such a move is not seen here.
/// If the node was in a verified hook subtree (it has a shadow), raw writes made to it this tick
/// may never be verified where it goes:
/// mark its subtree changed, drop its caches and shadows (marked again if it lands in a verified
/// subtree). Live nodes only (called with the node in hand), so no stale pointer / ABA issue.
pub fn onDetached(node: *Node) void {
    if (shadowOf(node) == null) return;
    detachRec(node);
}

fn detachRec(node: *Node) void {
    node_dirty.markUnmarkedRenderChange(node);
    node_render_cache.invalidateRenderCache(node);
    node_render_cache.invalidatePromotedRenderCache(node);
    node.invalidateSubtreePayloadCache();
    dropShadow(node);
    for (node.children.items) |child| detachRec(child);
}

fn dropSubtreeCaches(node: *Node) void {
    node_render_cache.invalidateRenderCache(node);
    node_render_cache.invalidatePromotedRenderCache(node);
    node.invalidateSubtreePayloadCache(); // memo + subtree payload + own payload
    for (node.children.items) |child| dropSubtreeCaches(child);
}

fn seqBefore(a: u32, b: u32) bool {
    return @as(i32, @bitCast(a -% b)) < 0;
}

/// Records this pass's result for a node. A hook node that was trusted by the previous pass and
/// is not now (it became excluded) drops the caches recorded under that trust.
fn setState(pass: *Pass, node: *Node, trusted: bool, chain_ok: bool) void {
    setStateRoot(pass, node, trusted, chain_ok, false);
}

fn setStateRoot(pass: *Pass, node: *Node, trusted: bool, chain_ok: bool, root: bool) void {
    const old = node.meta.per_frame.caches.hook_verify;
    if (!trusted and old.trusted and old.token == pass.token and old.seq == pass.seq -% 1) dropHookCaches(node);
    // ran_untrusted is consumed by this pass.
    node.meta.per_frame.caches.hook_verify = .{ .seq = pass.seq, .token = pass.token, .trusted = trusted, .chain_ok = chain_ok, .root = root };
}

/// An aborted pass did not verify this hook root: untrusted now, and its root / ran_untrusted bits
/// stay so that the next completed pass walks it (even if its hook is gone by then).
fn setStateAborted(pass: *Pass, node: *Node) void {
    const old = node.meta.per_frame.caches.hook_verify;
    if (old.trusted and old.token == pass.token and old.seq == pass.seq -% 1) dropHookCaches(node);
    node.meta.per_frame.caches.hook_verify = .{ .seq = pass.seq, .token = pass.token, .trusted = false, .chain_ok = false, .root = true, .ran_untrusted = true };
}

/// The previous pass of this Cx had this node as an outermost untrusted hook node.
fn wasRoot(pass: *const Pass, node: *const Node) bool {
    const old = node.meta.per_frame.caches.hook_verify;
    return old.root and old.token == pass.token and old.seq == pass.seq -% 1;
}

/// Hook node whose hooks the verification does not cover: a `main` hook (component hooks, today's
/// path for its subtree), except on an overlay root (z_index > 0, the plan's is_overlay_candidate:
/// Popover / Select / Notification content). An overlay root keeps its promoted / legacy overflow
/// surface across frames even with an untrusted hook (buildNodeExecutionPlan
/// overlay_root_before_render_cache_safe), and that surface contains its whole subtree, so its
/// subtree is verified like a `.subtree` hook's: a raw write marks the written node, which
/// invalidates the surface through the dirty bits; a translate (its anchored placement) only takes
/// the composite path, which keeps it. Other main-hook subtrees have no cache spanning them (their
/// hook node is untrusted: no promoted / legacy / subtree payload / memo there or above).
fn hookExcluded(node: *const Node) bool {
    return node.meta.per_frame.hooks.before_render.main != null and node.style.z_index() <= 0;
}

/// Outside any verified hook subtree: descend the flagged chain to the outermost untrusted hooks.
fn visitChain(pass: *Pass, node: *Node) bool {
    if (!node.frame_state.state_bits.flags.has_untrusted_before_render_subtree) return true;
    if (node.hasBeforeRenderHooks() and !node.beforeRenderHooksCacheTrusted()) {
        if (hookExcluded(node)) {
            setStateRoot(pass, node, false, false, true);
            return false;
        }
        const chain = walk(pass, node, true, false);
        if (pass.aborted) {
            setStateAborted(pass, node);
            return false;
        }
        const st = node.meta.per_frame.caches.hook_verify;
        setStateRoot(pass, node, st.trusted, st.chain_ok, true);
        pass.counters.verified_hooks += 1;
        return chain;
    }
    if (wasRoot(pass, node) or node.meta.per_frame.caches.hook_verify.ran_untrusted) {
        // Its untrusted hook is gone or now trusted (removeBeforeRender / a re-registration as
        // .dirty_marking, possibly in the very tick that made its last raw writes, possibly the
        // tick it was registered in): walk the subtree once more, so those writes and anything
        // the hook left are marked.
        const chain = walk(pass, node, true, false);
        if (pass.aborted) {
            setStateAborted(pass, node);
            return false;
        }
        setState(pass, node, true, chain);
        return chain;
    }
    var ok = true;
    for (node.children.items) |child| {
        if (!visitChain(pass, child)) ok = false;
    }
    setState(pass, node, true, ok);
    return ok;
}

/// Inside a verified hook subtree (`node` is the hook node itself when `is_root`): compare,
/// mark, refresh every node. Returns the chain state of `node` (no excluded hook below).
fn walk(pass: *Pass, node: *Node, is_root: bool, inherited_from_above: bool) bool {
    if (pass.aborted) return false;
    if (pass.budget == 0) {
        pass.aborted = true;
        return false;
    }
    pass.budget -= 1;
    pass.counters.nodes += 1;
    if (!is_root and node.hasBeforeRenderHooks() and !node.beforeRenderHooksCacheTrusted() and hookExcluded(node)) {
        // Nested component hook: its subtree keeps today's path. Its own node state is not
        // shadowed this pass (it is re-recorded), so its shadow goes stale (re-marked when it
        // comes back). A `main` hook assigned directly is only flagged when the tick first runs
        // it (and a quiet subtree is not ticked): flag it now, so that every ancestor sees an
        // untrusted subtree this frame (no splice / memo over it).
        if (!node.frame_state.state_bits.flags.has_untrusted_before_render_subtree)
            @import("../node_interaction.zig").markSubtreeUntrustedBeforeRenderHook(node);
        setState(pass, node, false, false);
        return false;
    }
    const inherited = verifyNode(pass, node, inherited_from_above);
    var chain = true;
    for (node.children.items) |child| {
        if (!walk(pass, child, false, inherited)) {
            if (child.frame_state.state_bits.flags.has_untrusted_before_render_subtree) chain = false;
        }
        if (pass.aborted) return false;
    }
    if (node.frame_state.state_bits.flags.has_untrusted_before_render_subtree) setState(pass, node, true, chain);
    return chain;
}

/// Compares, marks and refreshes one node. Returns whether its descendants must be marked for an
/// inherited text style change (here or above).
fn verifyNode(pass: *Pass, node: *Node, inherited_from_above: bool) bool {
    var raw: Raw = undefined;
    gather(&raw, pass.world, node);
    const st = pass.state;
    const fresh_shadow: ?*Shadow = if (shadowOf(node)) |s|
        (if (s.seq == st.seq -% 1 and s.generation == st.generation) s else null)
    else
        null;
    // No fresh shadow: anything may have changed since the caches were recorded.
    const diff: Diff = if (fresh_shadow) |s| compare(node, s, &raw) else .{ .own = true, .inherited = true };
    const unver = unverifiable(node, &raw);
    if (unver) pass.counters.unverifiable += 1;
    if (diff.own) pass.counters.diffs += 1;
    if (diff.own or unver or inherited_from_above) {
        node_dirty.markUnmarkedRenderChange(node);
        node_render_cache.invalidateRenderCache(node);
    } else if (diff.composite) {
        // Whatever bits are set already (a translate fast path keeps the own payload): the render
        // part of the API writers' marking (markCompositePropDirty); hit geometry is not updated
        // (see Diff.composite).
        pass.counters.diffs += 1;
        node_dirty.markUnmarkedTranslation(node);
    } else if (diff.translate) {
        const d = node.frame_state.state_bits.dirty;
        // Marked by markOwnTranslationDirty (fast path or full) already, else a raw write: the
        // full composite path, as a re-record would show it.
        // core.render alone re-records the content but does not bump composite / bubble the
        // composite bits a move needs.
        if (!(d.pipeline.transform or d.pipeline.composite)) {
            pass.counters.diffs += 1;
            node_dirty.markUnmarkedTranslation(node);
        }
    }
    if (diff.own) {
        if (!refresh(node, pass.allocator, &raw, st.seq, st.generation)) pass.aborted = true;
    } else {
        const s = fresh_shadow.?;
        // Unchanged (or translate / composite only): keep the copy, take this frame's values.
        s.style.translate_x = node.style.translate_x;
        s.style.translate_y = node.style.translate_y;
        if (diff.composite) {
            s.paint.opacity = raw.paint.opacity;
            if (node.style.ext) |e| inline for (composite_ext_fields) |name| {
                @field(s.ext, name) = @field(e.*, name);
            };
        }
        s.layout_revision = raw.revision;
        s.seq = st.seq;
    }
    return inherited_from_above or diff.inherited;
}

// ---------------------------------------------------------------------------------------------

test "raw_shadow audit compiles (field lists and pointer policy)" {
    // The comptime block above is the test; this keeps the module referenced.
    try std.testing.expect(pointer_policy.len > 0);
}

/// Bytes of the large optionals (ext_value_optionals) no reader can see, as a per-byte flag: the
/// payload of a null one, and the padding after the null flag. Layout: payload, then the null
/// flag byte (checked below), then padding.
fn extUnreadableBytes(e: *const StyleExt) [@sizeOf(StyleExt)]bool {
    var out: [@sizeOf(StyleExt)]bool = @splat(false);
    inline for (ext_value_optionals) |name| {
        const Child = @typeInfo(@FieldType(StyleExt, name)).optional.child;
        const off = @offsetOf(StyleExt, name);
        if (@field(e.*, name) == null) {
            for (off..off + @sizeOf(Child)) |i| out[i] = true;
        }
        for (off + @sizeOf(Child) + 1..off + @sizeOf(@FieldType(StyleExt, name))) |i| out[i] = true;
    }
    return out;
}

fn extFlagBytes() [@sizeOf(StyleExt)]bool {
    var out: [@sizeOf(StyleExt)]bool = @splat(false);
    inline for (ext_value_optionals) |name| {
        const Child = @typeInfo(@FieldType(StyleExt, name)).optional.child;
        comptime std.debug.assert(@sizeOf(@FieldType(StyleExt, name)) > @sizeOf(Child));
        out[@offsetOf(StyleExt, name) + @sizeOf(Child)] = true;
    }
    return out;
}

test "raw_shadow: extDiff gives the former two wordsEql verdicts for a change of any StyleExt byte (bar unreadable bytes of a large optional)" {
    try std.testing.expect(ext_value_optionals.len >= 2);
    var with_glass: StyleExt = .{ .shadow_count = 1, .gradient = .{ .from = types.Color.hex(0x112233), .to = types.Color.hex(0x445566) }, .corner_radius = .{ .all = 6 } };
    with_glass.glass = .{};
    with_glass.multi_gradient = .{ .stop_count = 2 };
    const plain: StyleExt = .{ .shadow_count = 1, .gradient = .{ .from = types.Color.hex(0x112233), .to = types.Color.hex(0x445566) }, .corner_radius = .{ .all = 6 } };
    const flags = extFlagBytes();
    for ([_]StyleExt{ plain, with_glass }) |base| {
        var a = base;
        // The null flag byte is what `== null` reads: 1 / 0 only.
        inline for (ext_value_optionals) |name| {
            const Child = @typeInfo(@FieldType(StyleExt, name)).optional.child;
            const flag = std.mem.asBytes(&a)[@offsetOf(StyleExt, name) + @sizeOf(Child)];
            try std.testing.expectEqual(@as(u8, @intFromBool(@field(a, name) != null)), flag);
        }
        const dead = extUnreadableBytes(&a);
        try std.testing.expect(extDiff(&a, &a).any == false);
        for (0..@sizeOf(StyleExt)) |k| {
            var b: StyleExt = undefined;
            @memcpy(std.mem.asBytes(&b), std.mem.asBytes(&a));
            const bytes = std.mem.asBytes(&b);
            if (flags[k]) bytes[k] ^= 1 else bytes[k] ^= 0x5a;
            const any = !wordsEql(StyleExt, &a, &b, &.{});
            const nc = !wordsEql(StyleExt, &a, &b, &composite_ext_fields);
            const got = extDiff(&a, &b);
            const got_rev = extDiff(&b, &a);
            if (dead[k] and !flags[k]) {
                // Only a byte no reader sees differs (a null payload, padding).
                try std.testing.expect(!got.any and !got.non_composite);
            } else {
                try std.testing.expectEqual(any, got.any);
                try std.testing.expectEqual(nc, got.non_composite);
            }
            try std.testing.expectEqual(got.any, got_rev.any);
            try std.testing.expectEqual(got.non_composite, got_rev.non_composite);
        }
    }
    // Composite fields only: any, not non_composite.
    var c = plain;
    c.scale_x = 1.5;
    c.rotate = 0.25;
    c.motion_offset = .{ 3, -2 };
    const d = extDiff(&plain, &c);
    try std.testing.expect(d.any and !d.non_composite);
}

test "raw_shadow: bytesEql agrees with std.mem.eql on every byte" {
    var prng = std.Random.DefaultPrng.init(0xb17e5);
    const r = prng.random();
    inline for (.{ TextProps, IconProps, ImageProps, PaintStateData, ComputedRect, node_mod.StickyOffset, types.Color, ?types.Color, nlo.NodeStroke, u8 }) |T| {
        var a: T = undefined;
        r.bytes(std.mem.asBytes(&a));
        for (0..@sizeOf(T)) |k| {
            var b: T = undefined;
            @memcpy(std.mem.asBytes(&b), std.mem.asBytes(&a));
            try std.testing.expect(bytesEql(T, &a, &b));
            std.mem.asBytes(&b)[k] ^= @as(u8, 1) << @intCast(k % 8);
            try std.testing.expectEqual(std.mem.eql(u8, std.mem.asBytes(&a), std.mem.asBytes(&b)), bytesEql(T, &a, &b));
            try std.testing.expect(!bytesEql(T, &a, &b));
        }
    }
}
