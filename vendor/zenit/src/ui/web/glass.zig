//! Web glass (docs/WEB_GLASS_DESIGN.md §5, P2): zenit's own glass pipeline —
//! render.backdrop_blur through the native RenderCommandEncoder — runs in wasm
//! on the record GPU backend; the browser replays the stream
//! (web/runtime/zenit-glass.mjs) with the WGSL generated from the same shaders.
//!
//! Per frame with glass: the encoder dispatches the frame's control tokens only
//! (clips, opacity layers, blur layers; encodeControlItems). Every
//! begin_blur_layer encodes exactly as on native (capture, banks, glass pass,
//! composite) against the *frame* texture, which the browser fills with the
//! backdrop (the items painted before each glass). Draw items stay with the
//! DOM / canvas islands.
//!
//! Output (zw_glass_*): the binary record stream + its strings and byte blob, and per glass item its
//! owner node, DOM host id and lowered item index, so the host can paint the
//! backdrop up to that item and place the composite in the element's glass layer.
const std = @import("std");
const gpu = @import("gpu");
const render = @import("render");
const core = @import("../core.zig");
const paint_table = @import("../core/paint_table.zig");
const Island = @import("canvas_island.zig").Island;

const a = std.heap.wasm_allocator;
const Backend = gpu.Backend;

extern "zenit" fn console_log(ptr: [*]const u8, len: usize) void;
fn logErr(comptime what: []const u8, err: anyerror) void {
    var buf: [128]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "[zenit glass] " ++ what ++ ": {s}", .{@errorName(err)}) catch return;
    console_log(msg.ptr, msg.len);
}

pub const State = struct {
    ready: bool = false,
    failed: bool = false,
    instance: Backend.Instance = undefined,
    adapters: []Backend.Adapter = &.{},
    device: Backend.Device = undefined,
    queue: Backend.Queue = undefined,
    sdf: render.SdfRenderer = undefined,
    text: render.TextRenderer = undefined,
    image: *render.ImageRenderer = undefined,
    icon: *render.IconRenderer = undefined,
    pool: render.OffscreenTexturePool = .{},
    persistent: render.PersistentGpuCache = .{},
    frame: ?Backend.Texture = null,
    /// The backdrop: the frame's items as a canvas-island stream with Op.mark
    /// before each glass (canvas_island.buildBackdrop).
    backdrop: Island = .{ .allocator = a },
    digest: u64 = 0,
    /// The stream differs from the previous frame's (the host re-executes it).
    changed: bool = false,
    /// This frame lowered at least one glass.
    active: bool = false,

    fn init(self: *State) !void {
        self.instance = try Backend.Instance.init(a, .{});
        self.adapters = try self.instance.enumerateAdapters();
        const dq = try self.adapters[0].requestDevice(a, .{});
        self.device = dq.device;
        self.queue = dq.queue;
        self.sdf = try render.SdfRenderer.init(a, &self.device);
        self.text = try render.TextRenderer.initWithoutShaper(a, &self.device);
        self.image = try a.create(render.ImageRenderer);
        try self.image.init(a, &self.device);
        self.icon = try a.create(render.IconRenderer);
        try self.icon.init(a, &self.device);
        self.ready = true;
    }

    /// Encode this frame's glass. `hostOf` maps a node id to its DOM host id (0: none).
    pub fn update(self: *State, cx: *core.Cx, hostOf: anytype) void {
        self.changed = false;
        if (self.failed) return;
        const items = cx.lowerForEncoderPaintTable();
        var any = false;
        for (items) |*it| if (it.isControl(.begin_blur_layer)) {
            any = true;
            break;
        };
        if (!any) {
            if (self.active) {
                self.active = false;
                self.changed = true;
                Backend.recorder.words.clearRetainingCapacity();
            }
            return;
        }
        self.active = true;
        if (!self.ready) self.init() catch |err| {
            logErr("init failed", err);
            self.failed = true;
            return;
        };
        self.encode(cx, items, hostOf) catch |err| {
            logErr("encode failed", err);
            Backend.recorder.words.clearRetainingCapacity();
        };
        self.backdrop.buildBackdrop(cx.lowering.web_lowered.items) catch |err| logErr("backdrop failed", err);
        const rec = Backend.recorder;
        var hh = std.hash.Wyhash.init(0);
        hh.update(std.mem.sliceAsBytes(rec.words.items));
        hh.update(rec.strings.items);
        hh.update(rec.blob.items);
        hh.update(std.mem.sliceAsBytes(self.backdrop.words.items));
        hh.update(self.backdrop.strings.items);
        hh.update(std.mem.sliceAsBytes(self.backdrop.points.items));
        const d = hh.final();
        self.changed = d != self.digest;
        self.digest = d;
    }

    fn encode(self: *State, cx: *core.Cx, items: []const paint_table.DisplayItem, hostOf: anytype) !void {
        const w = cx.viewport.width;
        const h = cx.viewport.height;
        const scale = cx.window_scale;
        const pw: u32 = @intFromFloat(@ceil(w * scale));
        const ph: u32 = @intFromFloat(@ceil(h * scale));
        if (pw == 0 or ph == 0) return error.EmptyWindow;
        if (self.frame) |f| if (f.size.width != pw or f.size.height != ph) {
            var old = f;
            old.destroy();
            self.frame = null;
        };
        if (self.frame == null) self.frame = try self.device.createTexture(a, .{
            .size = .{ .width = pw, .height = ph },
            .format = gpu.color_format,
            .usage = .{ .render_attachment = true, .copy_src = true, .copy_dst = true, .texture_binding = true },
        });
        const frame = &self.frame.?;


        // Retire luminance slots whose glass left the frame (AppRenderer.scanPaintTable):
        // the encoder starts each update at the same frame index, so slots never age out.
        const none = std.math.maxInt(u32);
        for (&self.persistent.luminance_slots) |*slot| {
            if (slot.key == none) continue;
            const live = for (items) |*it| {
                if (it.isControl(.begin_blur_layer) and it.glass_owner_id == slot.key) break true;
            } else false;
            if (!live) {
                slot.key = none;
                slot.value = null;
                slot.cur_pending = false;
                slot.prev_pending = false;
                // Free for the LRU: it only takes slots used before the current
                // frame, and every update encodes as frame 1.
                slot.last_used_frame = 0;
            }
        }
        // Blur-chain hysteresis (backdrop_blur level slots) counts consecutive frames; every
        // web update encodes as the same frame, so a slot's history never moves on: a node id
        // reused by another glass (story switch) inherited its committed depth for good. Each
        // update starts from fresh slots, as a page shown on its own does.
        for (&self.persistent.blur_level_slots) |*slot| slot.* = .{};
        const rec = Backend.recorder;
        rec.frame_texture = frame.id;
        rec.begin();
        self.persistent.beginFrame();
        self.pool.resetFrame();
        var gpu_encoder = try Backend.CommandEncoder.init(&self.queue);
        defer gpu_encoder.deinit();
        var view = frame.binding().createView();
        defer view.destroy();
        var pass = try gpu_encoder.beginRenderPass(.{ .color_attachments = &.{.{ .view = view, .load_op = .load, .store_op = .store, .clear_value = .TRANSPARENT }} });
        var enc = render.RenderCommandEncoder.initWithImageAndIcon(&self.sdf, &self.text, self.image, self.icon, &self.pool, &self.persistent);
        defer enc.deinit();
        enc.beginFrame(w, h, scale);
        enc.gpu_command_encoder = &gpu_encoder;
        enc.main_render_target = frame.binding();
        enc.render_pass = &pass;
        // Control tokens only: draws stay with the DOM and canvas islands.
        enc.encodeControlItems(items) catch {};
        if (enc.render_pass) |rp| {
            enc.flush(rp) catch {};
            rp.end();
        }
        var cmd = try gpu_encoder.finish();
        cmd.submit();
        enc.endPoolSession();

        rec.finish();
        // Host data after the GPU work: glass rows, luminance readbacks, scale.
        const f = rec.f;
        for (items, 0..) |*it, i| if (it.isControl(.begin_blur_layer)) {
            // Control tokens carry no paint node; the glass names its owner.
            const node = it.glass_owner_id;
            rec.emitAlways(.glass_row, &.{ node, hostOf.get(node), @intCast(i) });
        };
        // Backdrop luminance (AppRenderer.pollBackdropLuminance's input): the host
        // reads each pending staging back and publishes the means (publishLuminance).
        for (&self.persistent.luminance_slots) |*slot| {
            if (!slot.cur_pending) continue;
            slot.cur_pending = false;
            const staging = slot.staging orelse continue;
            const t = rec.indexOf(staging.id) orelse continue;
            var rows: [5 * 9 + 4]u32 = undefined;
            const cu = slot.content_uv;
            rows[0..9].* = .{ t, slot.cur_w, slot.cur_h, 1, slot.key, f(cu[0]), f(cu[1]), f(cu[0] + cu[2]), f(cu[1] + cu[3]) };
            var n: usize = 9;
            for (slot.shape_keys[0..slot.shape_count], slot.shape_uv[0..slot.shape_count]) |key, uv| {
                if (key == std.math.maxInt(u32) or n + 5 > rows.len) continue;
                rows[n..][0..5].* = .{ key, f(uv[0]), f(uv[1]), f(uv[2]), f(uv[3]) };
                rows[3] += 1;
                n += 5;
            }
            rec.emitAlways(.luminance, rows[0..n]);
        }
        rec.emitAlways(.scale, &.{f(scale)});
    }

    /// Backdrop luminance read back by the host: (node id, linear, sRGB) per
    /// region, the first region of each glass its own rect. Published like
    /// AppRenderer.pollBackdropLuminance; a change beyond 0.004 redraws.
    pub fn publishLuminance(self: *State, cx: *core.Cx, regions: []const [3]f32) void {
        _ = self;
        var changed = regions.len != cx.backdrop_luminance_region_count;
        var sum: f64 = 0;
        const n = @min(regions.len, cx.backdrop_luminance_regions.len);
        for (regions[0..n], 0..) |r, i| {
            const node: u32 = @bitCast(r[0]);
            const prev = cx.backdrop_luminance_regions[i];
            if (i >= cx.backdrop_luminance_region_count or prev.node_id != node or @abs(prev.lum - r[1]) > 0.004) changed = true;
            cx.backdrop_luminance_regions[i] = .{ .node_id = node, .lum = r[1], .lum_srgb = r[2] };
            sum += r[1];
        }
        cx.backdrop_luminance_region_count = n;
        if (n > 0) cx.backdrop_luminance = @floatCast(sum / @as(f64, @floatFromInt(n)));
        if (changed) cx.needs_redraw = true;
    }

    /// The stream (src/gpu/record/backend.zig recorder): records, strings, bytes.
    pub fn words(_: *const State) []const u32 {
        return Backend.recorder.words.items;
    }
    pub fn strings(_: *const State) []const u8 {
        return Backend.recorder.strings.items;
    }
    pub fn blob(_: *const State) []const u8 {
        return Backend.recorder.blob.items;
    }
};
