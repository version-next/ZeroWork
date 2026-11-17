//! Web DOM host runtime: the wasm side of `web/runtime/zenit-dom.mjs`.
//!
//! An app's wasm root declares
//!
//!     pub const panic = ui.web.panic;
//!     pub const std_options_debug_io = ui.web.io;
//!     comptime { ui.web.exportApp(App); }
//!
//! where `App.mount(cx, scope) !*ui.Node` builds the root view. The browser main
//! thread drives everything: input -> zenit Cx handlers (zenit hit testing, same
//! capture/bubble semantics as desktop), then `zw_frame` runs the native frame
//! order (timers, clock, layout, render, deferred work) and DomHost flushes the
//! diff into a command buffer that JS replays onto the DOM.
const std = @import("std");
const core = @import("../core.zig");
const reactive = @import("../reactive.zig");
const theme = @import("../theme.zig");
const events = @import("../events.zig");
const DomHost = @import("dom_host.zig").DomHost;
const IslandSet = @import("canvas_island.zig").IslandSet;

pub const io = @import("web_io.zig").io;
/// True when `io` carries the IndexedDB-backed filesystem (wasm32-wasi).
pub const has_fs = @import("web_io.zig").has_fs;

extern "zenit" fn panic_msg(ptr: [*]const u8, len: usize) void;
extern "zenit" fn measure_text(ptr: [*]const u8, len: usize, size: f32, weight: u16, italic: bool, mono: bool) f32;
extern "zenit" fn request_frame() void;
extern "zenit" fn console_log(ptr: [*]const u8, len: usize) void;
extern "zenit" fn load_encoded_texture(ptr: [*]const u8, len: usize) u32;
extern "zenit" fn utc_offset_minutes(epoch_seconds: f64) i32;
extern "zenit" fn download_file(name_ptr: [*]const u8, name_len: usize, mime_ptr: [*]const u8, mime_len: usize, ptr: [*]const u8, len: usize) void;
extern "zenit" fn open_file_picker(ptr: [*]const u8, len: usize, multiple: bool) void;

/// Local timezone offset (minutes east of UTC) at `epoch_seconds`, DST-aware
/// (the browser's zone; there is no libc localtime on the web).
fn requestFrame() void {
    request_frame();
}

pub fn utcOffsetMinutes(epoch_seconds: i64) i32 {
    return utc_offset_minutes(@floatFromInt(epoch_seconds));
}

/// Save bytes as a browser download (the web stand-in for writing to ~/Desktop).
/// Bytes are copied before returning.
pub fn downloadFile(name: []const u8, mime: []const u8, bytes: []const u8) void {
    download_file(name.ptr, name.len, mime.ptr, mime.len, bytes.ptr, bytes.len);
}

/// Synchronous PNG -> RGBA8 (straight alpha) for code that needs raw pixels
/// (export rasterizers, redaction). Other formats: error.NotPng.
pub const decodePng = @import("png_decode.zig").decode;
pub const DecodedImage = @import("png_decode.zig").Image;

/// Width/height from an encoded image header (PNG/JPEG/GIF/WebP/BMP).
pub const imageSize = @import("image.zig").imageSize;

/// Upload an encoded image (PNG/JPEG/GIF/WebP…) for `ui.image` nodes. The id is
/// valid immediately; the browser decodes asynchronously and the pixels appear
/// on a later frame (DOM and canvas islands both pick them up).
pub fn loadEncodedTexture(bytes: []const u8) u32 {
    return load_encoded_texture(bytes.ptr, bytes.len);
}

/// Ask the browser for files (`accept` like "image/*"). Chosen files are written
/// into the VFS under /tmp/picked/ and delivered as a platform drop
/// (DragEvent .dropped, payload .file_or_url, paths newline-separated) at the
/// center of the window — exactly like a Finder drop on desktop.
pub fn openFilePicker(accept: []const u8, multiple: bool) void {
    open_file_picker(accept.ptr, accept.len, multiple);
}

/// Log a line to the browser console (apps have no stderr on the web).
pub fn consoleLog(msg: []const u8) void {
    console_log(msg.ptr, msg.len);
}

pub const panic = std.debug.FullPanic(struct {
    fn f(msg: []const u8, _: ?usize) noreturn {
        panic_msg(msg.ptr, msg.len);
        @trap();
    }
}.f);

fn measureProp(p: [*]const u8, n: usize, size: f32, w: u16, it: bool) f32 {
    return measure_text(p, n, size, w, it, false);
}
fn measureMono(p: [*]const u8, n: usize, size: f32, w: u16, it: bool) f32 {
    return measure_text(p, n, size, w, it, true);
}

pub const State = struct {
    cx: *core.Cx,
    scope: *reactive.Scope,
    host: DomHost,
    islands: IslandSet,
    /// zenit's glass pipeline on the record backend (glass.zig); void when the
    /// app opts out (`pub const zenit_web_glass = false;` in its root file).
    glass: if (glass_enabled) @import("glass.zig").State else void = if (glass_enabled) .{} else {},
    force: bool = true,
};

/// WebGPU glass tier (docs/WEB_GLASS_DESIGN.md §5). An app without glass declares
/// `pub const zenit_web_glass = false;` in its root file: the renderer is then not
/// compiled in and the glass stays on the CSS tier.
const glass_enabled = if (@hasDecl(@import("root"), "zenit_web_glass")) @import("root").zenit_web_glass else true;

/// node id -> DOM host id, for the glass stream (glass.zig).
const HostOf = struct {
    host: *const DomHost,
    pub fn get(self: HostOf, node: u32) u32 {
        var it = self.host.live.iterator();
        while (it.next()) |e| if (e.value_ptr.node.id == node) return e.key_ptr.*;
        return 0;
    }
};

/// Paint `node`'s subtree into a WebGPU <canvas> instead of mirroring it as DOM
/// (big custom-drawn surfaces: boards, charts). One island per app for now;
/// null removes it. Input still flows through zenit hit testing.
pub fn setCanvasIsland(node: ?*core.Node) void {
    const s = state orelse return;
    s.islands.explicit = node;
    s.force = true;
}
pub var state: ?*State = null;
var lum_buf: [288][3]f32 = undefined;

fn st() *State {
    return state orelse @panic("web host: zw_init not called");
}

fn mods(bits: u32) events.Modifiers {
    return .{ .shift = bits & 1 != 0, .ctrl = bits & 2 != 0, .alt = bits & 4 != 0, .super = bits & 8 != 0 };
}

pub fn exportApp(comptime App: type) void {
    const E = struct {
        /// Layout domains on (default) / M0 all-absolute mirror (A-B, diagnostics).
        fn setCssLayout(on: u32) callconv(.c) void {
            const s = state orelse return;
            s.host.setCssLayout(on != 0);
            s.force = true;
        }
        fn init(w: f32, h: f32, dpr: f32, dark: bool) callconv(.c) u32 {
            const a = std.heap.wasm_allocator;
            const s = a.create(State) catch return 1;
            const cx = core.Cx.init(a, io) catch return 2;
            // Inbox.notify (main thread: wasm here is single-threaded) asks the page for a frame.
            cx.setWakeHandler(requestFrame);
            cx.tokens = if (dark) &theme.dark else &theme.light;
            cx.text.measure_fn = measureProp;
            // Input/Textarea are native <input>/<textarea> here (dom_host syncField).
            core.host_native_text_fields = true;
            @import("../core/text_layout.zig").setMonospaceMeasureFn(measureMono);
            s.* = .{ .cx = cx, .scope = undefined, .host = undefined, .islands = .{ .allocator = a } };
            // Subscribe before the first node exists (host contract).
            s.host.init(a);
            s.scope = reactive.Scope.init(a, null, cx.owner) catch return 3;
            cx.setWindowMetrics(w, h, dpr);
            state = s;
            const root = App.mount(cx, s.scope) catch |err| {
                var buf: [96]u8 = undefined;
                consoleLog(std.fmt.bufPrint(&buf, "App.mount failed: {s}", .{@errorName(err)}) catch "App.mount failed");
                return 4;
            };
            cx.root = root;
            return 0;
        }
        fn frame() callconv(.c) i32 {
            const s = st();
            const cx = s.cx;
            cx.fireDueTimers();
            // App work that must not run inside an event dispatch (e.g. whole-tree rebuilds).
            if (@hasDecl(App, "beforeFrame")) App.beforeFrame(cx);
            if (s.force or cx.wantsFrame()) {
                s.force = false;
                // Frame-first delivery (Inbox callbacks) before this frame's layout.
                _ = cx.deliverInboxes();
                cx.advanceFrameClock();
                cx.layout();
                _ = cx.render();
                s.islands.update(cx, s.host.live.iterator()) catch {};
                s.host.islands = &s.islands;
                s.host.flush(cx);
                if (comptime glass_enabled) s.glass.update(cx, HostOf{ .host = &s.host });
            }
            if (s.host.force_resync) {
                // A volatile value settled (e.g. opacity after a fade): one more flush
                // folds it back into an atomic class.
                s.host.force_resync = false;
                s.force = true;
                return 16; // ms
            }
            if (cx.hasReadyWork()) _ = cx.drainDeferredWork(cx.deferredBudgetUs());
            if (cx.needs_redraw or cx.inboxPending() or cx.hasPendingSceneWork()) return 0;
            const delay = cx.nextWakeDelayNs() orelse return -1;
            return @intCast(@min(delay / std.time.ns_per_ms, 60_000));
        }
        fn cmdsPtr() callconv(.c) [*]const u32 {
            return st().host.cmds.items.ptr;
        }
        fn cmdsLen() callconv(.c) usize {
            return st().host.cmds.items.len;
        }
        fn strsPtr() callconv(.c) [*]const u8 {
            return st().host.strings.items.ptr;
        }
        fn consumed() callconv(.c) void {
            st().host.reset();
        }
        fn resize(w: f32, h: f32, dpr: f32) callconv(.c) void {
            st().cx.setWindowMetrics(w, h, dpr);
            st().force = true;
        }
        /// Browser hit stack for the next pointer/wheel/drop event: host ids of the
        /// mirrored elements under the point, topmost first (written by JS into
        /// `hit_buf`); `fallback` = a canvas island is under the point -> zenit
        /// hit-tests its coordinates when no DOM node answers.
        var hit_buf: [32]u32 = undefined;
        fn hitBufPtr() callconv(.c) [*]u32 {
            return &hit_buf;
        }
        fn hostTarget(len: u32, fallback: u32) void {
            const s = st();
            if (!s.host.css_layout) {
                s.cx.setHostHitStack(false, &.{}, true);
                return;
            }
            var nodes: [32]*core.Node = undefined;
            var n: usize = 0;
            for (hit_buf[0..@min(len, hit_buf.len)]) |id| {
                if (s.host.live.get(id)) |m| {
                    nodes[n] = @constCast(m.node);
                    n += 1;
                }
            }
            s.cx.setHostHitStack(true, nodes[0..n], fallback != 0);
        }
        /// Box-model audit (dev): logs `ABS {json}` for every absolute node with an auto
        /// inset pair whose static position depends on padding, i.e. every node moved by
        /// zenit's static-position rule (content edge of the containing block) and every
        /// node where that rule differs from CSS (static parent != containing block).
        fn absAudit() callconv(.c) void {
            const s = st();
            var it = s.host.live.iterator();
            var buf: [512]u8 = undefined;
            while (it.next()) |e| {
                const n = e.value_ptr.node;
                if (n.style.position != .absolute) continue;
                const parent = n.parent orelse continue;
                const ins = n.style.inset();
                const sx = ins.left == .auto and ins.right == .auto;
                const sy = ins.top == .auto and ins.bottom == .auto;
                if (!sx and !sy) continue;
                var cb: *const core.Node = parent;
                while (!(cb.style.position != .static or cb.style.layout_isolation or cb.style.translate_x != 0 or cb.style.translate_y != 0)) cb = cb.parent orelse break;
                const px = if (sx) cb.style.padding.left else 0;
                const py = if (sy) cb.style.padding.top else 0;
                const ppx = if (sx) parent.style.padding.left else 0;
                const ppy = if (sy) parent.style.padding.top else 0;
                if (px == 0 and py == 0 and (cb == parent or (ppx == 0 and ppy == 0))) continue;
                const line = std.fmt.bufPrint(&buf, "ABS {{\"id\":{d},\"sx\":{},\"sy\":{},\"cb_pad\":[{d},{d}],\"parent_is_cb\":{},\"parent_pad\":[{d},{d}],\"tx\":{d},\"ty\":{d}}}", .{ e.key_ptr.*, sx, sy, px, py, cb == parent, ppx, ppy, n.style.translate_x, n.style.translate_y }) catch continue;
                consoleLog(line);
            }
        }
        fn hostTargetExport(hit_len: u32, fallback: u32) callconv(.c) void {
            hostTarget(hit_len, fallback);
        }
        fn pointerAt(kind: u32, x: f32, y: f32, button: u32, m: u32, hit_len: u32, fallback: u32) callconv(.c) void {
            hostTarget(hit_len, fallback);
            pointer(kind, x, y, button, m);
        }
        /// True when zenit used the wheel (the host then stops the browser default).
        fn wheelAt(dx: f32, dy: f32, x: f32, y: f32, m: u32, hit_len: u32, fallback: u32) callconv(.c) bool {
            hostTarget(hit_len, fallback);
            return st().cx.handleScrollConsumed(.{ .dx = dx, .dy = dy, .x = x, .y = y, .modifiers = mods(m) });
        }
        fn pointer(kind: u32, x: f32, y: f32, button: u32, m: u32) callconv(.c) void {
            const cx = st().cx;
            const b: events.MouseButton = switch (button) {
                1 => .middle,
                2 => .right,
                else => .left,
            };
            switch (kind) {
                0 => cx.handleMouseMoveEx(x, y, mods(m)),
                1 => cx.handleMouseDownEx(x, y, b, mods(m)),
                2 => cx.handleMouseUpEx(x, y, b, mods(m)),
                else => cx.handlePointerLeave(),
            }
        }
        fn wheel(dx: f32, dy: f32, x: f32, y: f32, m: u32) callconv(.c) void {
            st().cx.handleScroll(.{ .dx = dx, .dy = dy, .x = x, .y = y, .modifiers = mods(m) });
        }
        /// JS wrote dropped/picked files into the VFS; deliver them like a native drop.
        fn drop(x: f32, y: f32, ptr: [*]const u8, len: usize) callconv(.c) void {
            const cx = st().cx;
            cx.handlePlatformDrag(x, y, @backingInt(events.DragEvent.Kind.dropped), ptr[0..len], @backingInt(events.DragEvent.PayloadKind.file_or_url), false, true);
        }
        fn dragOver(kind: u32, x: f32, y: f32) callconv(.c) void {
            st().cx.handlePlatformDrag(x, y, @intCast(kind), "", @backingInt(events.DragEvent.PayloadKind.file_or_url), false, true);
        }
        /// Diagnostics: host id of the node zenit hit-tests at (x, y); 0 = none.
        /// Layout-domain conformance probe: [id, x, y, w, h(f32 bits)] per mirrored
        /// node, zenit's global rect (layout + translates). e2e compares these with
        /// getBoundingClientRect to gate browser layout against the zenit engine.
        var probe_buf: std.ArrayListUnmanaged(u32) = .empty;
        fn layoutProbe() callconv(.c) u32 {
            const s = st();
            probe_buf.clearRetainingCapacity();
            var it = s.host.live.iterator();
            while (it.next()) |entry| {
                const n = entry.value_ptr.node;
                if (n.freeing or n.tag == .anchor) continue;
                const r = n.globalRect();
                const w = [_]u32{ entry.key_ptr.*, @bitCast(r.x), @bitCast(r.y), @bitCast(r.w), @bitCast(r.h) };
                probe_buf.appendSlice(std.heap.wasm_allocator, &w) catch return 0;
            }
            return @intCast(probe_buf.items.len);
        }
        fn layoutProbePtr() callconv(.c) [*]u32 {
            return probe_buf.items.ptr;
        }
        /// Native field edits (dom_host syncField): the browser owns editing; zenit's
        /// model takes the value/selection through the a11y editable-text contract.
        fn fieldNode(id: u32) ?*core.Node {
            const m = st().host.live.get(id) orelse return null;
            return @constCast(m.node);
        }
        /// Growable UTF-8 buffer for field values (a textarea can exceed input_buf).
        var field_buf: std.ArrayListUnmanaged(u8) = .empty;
        fn fieldBuf(len: u32) callconv(.c) ?[*]u8 {
            field_buf.resize(std.heap.wasm_allocator, len) catch return null;
            return field_buf.items.ptr;
        }
        fn fieldInput(id: u32, len: u32, s0: u32, s1: u32) callconv(.c) void {
            const n = fieldNode(id) orelse return;
            const a = n.behavior.interaction.a11y orelse return;
            const et = a.editable_text orelse return;
            if (et.set_value) |set| _ = set(et.context, field_buf.items[0..@min(len, field_buf.items.len)]);
            // set_value may republish editable_text; read it again for the selection.
            if (n.behavior.interaction.a11y) |a2| if (a2.editable_text) |et2| {
                _ = et2.set_selection(et2.context, s0, s1);
            };
            st().force = true;
        }
        fn fieldSelect(id: u32, s0: u32, s1: u32) callconv(.c) void {
            const n = fieldNode(id) orelse return;
            const a = n.behavior.interaction.a11y orelse return;
            const et = a.editable_text orelse return;
            _ = et.set_selection(et.context, s0, s1);
            st().force = true;
        }
        /// The native <input>/<textarea> scrolled its text (scrollLeft/scrollTop): zenit's
        /// Input/Textarea follows, so its layout and overflow fades match the browser.
        fn fieldScroll(id: u32, x: f32, y: f32) callconv(.c) void {
            const n = fieldNode(id) orelse return;
            const a = n.behavior.interaction.a11y orelse return;
            const et = a.editable_text orelse return;
            const set = et.set_scroll orelse return;
            if (set(et.context, x, y)) st().force = true;
        }
        /// A key went to a native field (the browser edits; zenit's key path never saw
        /// it): keyboard modality, so the control shows its focus-visible ring as natively.
        fn fieldKeyModality() callconv(.c) void {
            const fm = &st().cx.focus_manager;
            if (fm.focus_visible) return;
            fm.noteInputModality(.keyboard);
            st().force = true;
        }
        fn fieldFocus(id: u32, on: u32) callconv(.c) void {
            const cx = st().cx;
            if (on != 0) {
                const n = fieldNode(id) orelse return;
                if (cx.focus_manager.getFocused() != n) cx.setFocus(n);
            } else if (fieldNode(id)) |n| {
                if (cx.focus_manager.getFocused() == n) cx.clearFocus();
            }
            st().force = true;
        }
        /// The browser scrolled a native scroller (dom_host syncScroll): fold the DOM
        /// offset into zenit's ScrollState. The mirror records the browser's value so a
        /// pixel-snapped echo is not pushed back mid-gesture.
        fn scrollSet(id: u32, x: f32, y: f32) callconv(.c) void {
            const set = core.host_scroll_set_hook orelse return;
            const m = st().host.live.getPtr(id) orelse return;
            m.scroll_x = x;
            m.scroll_y = y;
            if (set(@constCast(m.node), x, y)) st().force = true;
        }
        fn hitAt(x: f32, y: f32) callconv(.c) u32 {
            const n = st().cx.hitTest(x, y) orelse return 0;
            return @intCast(n.host_id);
        }
        fn magnify(m: f32, x: f32, y: f32) callconv(.c) void {
            st().cx.handleMagnify(m, x, y, .changed);
        }
        fn key(down: bool, code: u32, m: u32) callconv(.c) bool {
            const k = std.enums.fromInt(events.KeyCode, code) orelse return false;
            // Key down: true only when zenit consumed it (the host then stops the
            // browser default); unconsumed keys stay browser shortcuts.
            if (down) return st().cx.handleKeyDownConsumed(k, mods(m));
            st().cx.handleKeyUp(k, mods(m));
            return true;
        }
        var input_buf: [1024]u8 = undefined;
        fn inputBuf() callconv(.c) [*]u8 {
            return &input_buf;
        }
        fn text(len: usize) callconv(.c) void {
            st().cx.handleTextInput(input_buf[0..@min(len, input_buf.len)]);
        }
        fn clipboardMirror(len: usize) callconv(.c) void {
            @import("clipboard.zig").setMirror(input_buf[0..@min(len, input_buf.len)]);
        }
        fn imePreedit(len: usize, caret_byte: u32) callconv(.c) void {
            st().cx.handleImePreedit(input_buf[0..@min(len, input_buf.len)], caret_byte);
        }
        fn imeCommit(len: usize) callconv(.c) void {
            st().cx.handleImeCommit(input_buf[0..@min(len, input_buf.len)]);
        }
        var caret_out: [4]f32 = .{ 0, 0, 0, 0 };
        /// First caret rect (window px) for IME candidate placement; 0 = none.
        fn caret() callconv(.c) u32 {
            const cx = st().cx;
            if (cx.caret_rect_count == 0) return 0;
            caret_out = cx.caret_rects[0];
            return @intCast(cx.caret_rect_count);
        }
        fn caretPtr() callconv(.c) [*]const f32 {
            return &caret_out;
        }
        // ── canvas islands (WebGPU), indexed 0..zw_islands_count ──
        fn islandsCount() callconv(.c) u32 {
            return @intCast(st().islands.islands.items.len);
        }
        fn isl(i: u32) *@import("canvas_island.zig").Island {
            return st().islands.islands.items[i];
        }
        fn islandRoot(i: u32) callconv(.c) u32 {
            return @intCast(isl(i).root_id);
        }
        fn islandChanged(i: u32) callconv(.c) bool {
            const x = isl(i);
            defer x.changed = false;
            return x.changed;
        }
        fn islandWordsPtr(i: u32) callconv(.c) [*]const u32 {
            return isl(i).words.items.ptr;
        }
        fn islandWordsLen(i: u32) callconv(.c) usize {
            return isl(i).words.items.len;
        }
        fn islandStrsPtr(i: u32) callconv(.c) [*]const u8 {
            return isl(i).strings.items.ptr;
        }
        fn islandPtsPtr(i: u32) callconv(.c) [*]const f32 {
            return isl(i).points.items.ptr;
        }
        fn cursor() callconv(.c) u32 {
            return @backingInt(st().cx.current_cursor);
        }
    };
    @import("web_io.zig").exportVfs();
    @export(&E.init, .{ .name = "zw_init" });
    @export(&E.setCssLayout, .{ .name = "zw_set_css_layout" });
    @export(&E.frame, .{ .name = "zw_frame" });
    @export(&E.cmdsPtr, .{ .name = "zw_cmds_ptr" });
    @export(&E.cmdsLen, .{ .name = "zw_cmds_len" });
    @export(&E.strsPtr, .{ .name = "zw_strs_ptr" });
    @export(&E.consumed, .{ .name = "zw_consumed" });
    @export(&E.resize, .{ .name = "zw_resize" });
    @export(&E.pointer, .{ .name = "zw_pointer" });
    @export(&E.wheel, .{ .name = "zw_wheel" });
    @export(&E.key, .{ .name = "zw_key" });
    @export(&E.magnify, .{ .name = "zw_magnify" });
    @export(&E.hitAt, .{ .name = "zw_hit_at" });
    @export(&E.fieldBuf, .{ .name = "zw_field_buf" });
    @export(&E.fieldInput, .{ .name = "zw_field_input" });
    @export(&E.fieldScroll, .{ .name = "zw_field_scroll" });
    @export(&E.fieldKeyModality, .{ .name = "zw_field_key_modality" });
    @export(&E.absAudit, .{ .name = "zw_debug_abs_audit" });
    @export(&E.fieldSelect, .{ .name = "zw_field_select" });
    @export(&E.fieldFocus, .{ .name = "zw_field_focus" });
    @export(&E.scrollSet, .{ .name = "zw_scroll_set" });
    @export(&E.pointerAt, .{ .name = "zw_pointer_at" });
    @export(&E.hitBufPtr, .{ .name = "zw_hit_buf" });
    @export(&E.hostTargetExport, .{ .name = "zw_host_target" });
    @export(&E.wheelAt, .{ .name = "zw_wheel_at" });
    @export(&E.layoutProbe, .{ .name = "zw_layout_probe" });
    @export(&E.layoutProbePtr, .{ .name = "zw_layout_probe_ptr" });
    @export(&E.drop, .{ .name = "zw_drop" });
    @export(&E.dragOver, .{ .name = "zw_drag_over" });
    @export(&E.inputBuf, .{ .name = "zw_input_buf" });
    @export(&E.text, .{ .name = "zw_text" });
    @export(&E.imePreedit, .{ .name = "zw_ime_preedit" });
    @export(&E.clipboardMirror, .{ .name = "zw_clipboard_mirror" });
    @export(&E.imeCommit, .{ .name = "zw_ime_commit" });
    @export(&E.caret, .{ .name = "zw_caret" });
    @export(&E.caretPtr, .{ .name = "zw_caret_ptr" });
    @export(&E.cursor, .{ .name = "zw_cursor" });
    @export(&E.islandsCount, .{ .name = "zw_islands_count" });
    @export(&E.islandRoot, .{ .name = "zw_island_root" });
    @export(&E.islandChanged, .{ .name = "zw_island_changed" });
    @export(&E.islandWordsPtr, .{ .name = "zw_island_words_ptr" });
    @export(&E.islandWordsLen, .{ .name = "zw_island_words_len" });
    @export(&E.islandStrsPtr, .{ .name = "zw_island_strs_ptr" });
    @export(&E.islandPtsPtr, .{ .name = "zw_island_pts_ptr" });
    if (glass_enabled) {
        const G = struct {
        // ── glass stream (glass.zig; web/runtime/zenit-glass.mjs) ──
            fn glassChanged() callconv(.c) u32 {
                const g = &st().glass;
                defer g.changed = false;
                return @intFromBool(g.changed) | (@as(u32, @intFromBool(g.active)) << 1);
            }
            /// The host's glass replayer just became ready: resend the stream.
            fn glassInvalidate() callconv(.c) void {
                const s = st();
                s.glass.digest = 0;
                s.force = true;
            }
            fn glassWordsPtr() callconv(.c) [*]const u32 {
                return st().glass.words().ptr;
            }
            fn glassWordsLen() callconv(.c) usize {
                return st().glass.words().len;
            }
            fn glassStrsPtr() callconv(.c) [*]const u8 {
                return st().glass.strings().ptr;
            }
            fn glassStrsLen() callconv(.c) usize {
                return st().glass.strings().len;
            }
            fn glassBlobPtr() callconv(.c) [*]const u8 {
                return st().glass.blob().ptr;
            }
            fn glassBlobLen() callconv(.c) usize {
                return st().glass.blob().len;
            }
            /// Luminance readings: n x (node id bits, linear, sRGB) written at zw_glass_lum_buf.
            fn glassLumBuf() callconv(.c) [*][3]f32 {
                return &lum_buf;
            }
            fn glassLumPublish(n: u32) callconv(.c) void {
                const s = st();
                s.glass.publishLuminance(s.cx, lum_buf[0..@min(n, lum_buf.len)]);
            }
            fn glassBackdropWordsPtr() callconv(.c) [*]const u32 {
                return st().glass.backdrop.words.items.ptr;
            }
            fn glassBackdropWordsLen() callconv(.c) usize {
                return st().glass.backdrop.words.items.len;
            }
            fn glassBackdropStrsPtr() callconv(.c) [*]const u8 {
                return st().glass.backdrop.strings.items.ptr;
            }
            fn glassBackdropStrsLen() callconv(.c) usize {
                return st().glass.backdrop.strings.items.len;
            }
            fn glassBackdropPtsPtr() callconv(.c) [*]const f32 {
                return st().glass.backdrop.points.items.ptr;
            }
            fn glassBackdropPtsLen() callconv(.c) usize {
                return st().glass.backdrop.points.items.len;
            }
        };
        @export(&G.glassChanged, .{ .name = "zw_glass_changed" });
        @export(&G.glassInvalidate, .{ .name = "zw_glass_invalidate" });
        @export(&G.glassWordsPtr, .{ .name = "zw_glass_words_ptr" });
        @export(&G.glassWordsLen, .{ .name = "zw_glass_words_len" });
        @export(&G.glassStrsPtr, .{ .name = "zw_glass_strs_ptr" });
        @export(&G.glassStrsLen, .{ .name = "zw_glass_strs_len" });
        @export(&G.glassBlobPtr, .{ .name = "zw_glass_blob_ptr" });
        @export(&G.glassBlobLen, .{ .name = "zw_glass_blob_len" });
        @export(&G.glassLumBuf, .{ .name = "zw_glass_lum_buf" });
        @export(&G.glassLumPublish, .{ .name = "zw_glass_lum_publish" });
        @export(&G.glassBackdropWordsPtr, .{ .name = "zw_glass_backdrop_words_ptr" });
        @export(&G.glassBackdropWordsLen, .{ .name = "zw_glass_backdrop_words_len" });
        @export(&G.glassBackdropStrsPtr, .{ .name = "zw_glass_backdrop_strs_ptr" });
        @export(&G.glassBackdropStrsLen, .{ .name = "zw_glass_backdrop_strs_len" });
        @export(&G.glassBackdropPtsPtr, .{ .name = "zw_glass_backdrop_pts_ptr" });
        @export(&G.glassBackdropPtsLen, .{ .name = "zw_glass_backdrop_pts_len" });
    }
}
