//! Real-window material probe. It mounts the production GlassBox component.
const std = @import("std");
const ui = @import("ui");
const runtime = @import("zenit_app");
const Glass = ui.widgets.glass_box;
extern fn metal_glass_clock_trace_enabled() bool;
extern fn metal_glass_clock_trace_host_time() f64;
extern fn metal_glass_clock_trace_line(line: [*]const u8, length: usize) void;
extern fn macos_glass_clock_trace_display_tick(window: *anyopaque, times: *[2]f64) u64;
const Scene = struct {
    id: []const u8,
    background: []const u8,
    variant: []const u8,
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    radius: f32,
    tint: ?[3]u8 = null,
    /// `tintColor` alpha (null = opaque).
    tint_alpha: ?u8 = null,
    /// Glass idiom profile ("macos" default / "ios").
    idiom: ?[]const u8 = null,
    foreground: ?[]const u8 = null,
    /// Diagnostic fixtures select the appearance explicitly; gate fixtures
    /// keep deriving it from the background name.
    scheme: ?[]const u8 = null,
};
var g_app: *runtime.App = undefined;
var g_scenes: []const Scene = &.{};
const background_names = [_][]const u8{ "light", "dark", "mixed", "text-light", "text-mixed" };
var g_textures: [background_names.len]u32 = undefined;
var g_scene_textures: []u32 = &.{};
var g_background: *ui.Node = undefined;
const foreground_names = [_][]const u8{ "foreground-regular-panel", "foreground-clear-panel", "foreground-toolbar" };
var g_foreground_textures: [foreground_names.len]u32 = undefined;
var g_foreground: *ui.Node = undefined;
var g_glass: Glass.GlassBoxMount = undefined;
var g_scroll: ui.widgets.ScrollAreaResult = undefined;
var g_drag: *ui.interaction.drag.Binding = undefined;
var g_drag_handler: @TypeOf(@as(ui.Node, undefined).behavior.events.on_event) = null;
var g_motion = false;
var g_drag_moves: usize = 0;
var g_clock_trace_morph_start_ms: f64 = 0;
var g_clock_trace_event: u64 = 0;
var g_quit = std.atomic.Value(bool).init(false);
// Calibration uses the same production render hook, then changes only public
// optical parameters. /glass/setup always clears this patch for gate captures.
const Tune = struct {
    backdrop_blur: ?f32 = null,
    backdrop_brightness: ?f32 = null,
    backdrop_saturation: ?f32 = null,
    warp_gain: ?f32 = null,
    center_thickness: ?f32 = null,
    bezel_width: ?f32 = null,
    specular_opacity: ?f32 = null,
    refraction_level: ?f32 = null,
    blur_level: ?f32 = null,
    magnification: ?f32 = null,
    glass_intensity: ?f32 = null,
    edge_field_strength: ?f32 = null,
    backdrop_distance: ?f32 = null,
    tint_alpha: ?u8 = null,
    tint: ?[4]u8 = null,
};
var g_tune: Tune = .{};
fn terminate(_: std.posix.SIG) callconv(.c) void {
    g_quit.store(true, .release);
}

fn emitClockTrace(comptime format: []const u8, args: anytype) void {
    var storage: [1400]u8 = undefined;
    const line = std.fmt.bufPrint(&storage, format, args) catch return;
    metal_glass_clock_trace_line(line.ptr, line.len);
}

fn traceMotionPose() void {
    if (!g_motion or !metal_glass_clock_trace_enabled()) return;
    const host_time = metal_glass_clock_trace_host_time();
    var display_times: [2]f64 = .{ 0, 0 };
    const display_tick = macos_glass_clock_trace_display_tick(g_app.win.window_ptr, &display_times);
    const style = g_glass.box.style;
    const rect = g_glass.box.rectFromWorldOrFallback();
    const x = if (style.ext) |ext| ext.inset.left.resolve(640) orelse rect.x else rect.x;
    const y = if (style.ext) |ext| ext.inset.top.resolve(480) orelse rect.y else rect.y;
    const w = switch (style.width) {
        .px => |value| value,
        else => rect.w,
    };
    const h = switch (style.height) {
        .px => |value| value,
        else => rect.h,
    };
    const morph_t: f32 = if (g_glass.state.morph) |m| m.t else if (g_clock_trace_morph_start_ms > 0) 1 else 0;
    const animation_elapsed = if (g_glass.state.morph) |m| m.transaction_clock.last_elapsed_ms else 0;
    const transaction_anchor = if (g_glass.state.morph) |m| m.transaction_clock.target_anchor_ms orelse 0 else 0;
    const sampled_tick = if (g_app.cx.frame_presentation_sample) |sample| sample.tick else 0;
    const sampled_target = if (g_app.cx.frame_presentation_sample) |sample| (sample.target_time_ms orelse 0) / 1000 else 0;
    emitClockTrace("{{\"kind\":\"pose\",\"frame\":{d},\"event\":{d},\"host_time\":{d:.9},\"frame_time_ms\":{d:.6},\"frame_dt_ms\":{d:.6},\"morph_active\":{},\"morph_start_ms\":{d:.6},\"morph_t\":{d:.6},\"style_rect\":[{d:.6},{d:.6},{d:.6},{d:.6}],\"display_tick\":{d},\"display_callback_time\":{d:.9},\"display_target_time\":{d:.9},\"animation_elapsed_ms\":{d:.6},\"transaction_target_anchor_ms\":{d:.6},\"sampled_display_tick\":{d},\"sampled_display_target_time\":{d:.9}}}", .{
        g_app.renderer.frame_count + 1, g_clock_trace_event,  host_time,
        g_app.cx.frame_time_ms,         g_app.cx.frame_dt_ms, g_glass.state.morph != null,
        g_clock_trace_morph_start_ms,   morph_t,              x,
        y,                              w,                    h,
        display_tick,                   display_times[0],     display_times[1],
        animation_elapsed,              transaction_anchor,   sampled_tick,
        sampled_target,
    });
}

fn mount(cx: *ui.Cx, scope: *ui.Scope) !*ui.Node {
    cx.setTheme(&ui.theme.light);
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .position = .relative }, .{});
    g_background = try ui.image(cx, g_textures[0], .{ .width = .fixed(640), .height = .fixed(480), .position = .absolute });
    try root.appendChild(cx.allocator, g_background);
    g_scroll = try ui.widgets.ScrollArea(.{ .width = 640, .height = 480, .content_height = 960 }).mount(scope, cx);
    g_scroll.container.style.position = .absolute;
    g_scroll.container.style.display = .none;
    // Match the native scroll fixture, whose indicators are hidden.
    for (g_scroll.container.children.items) |child| if (child != g_scroll.content) {
        child.style.display = .none;
    };
    for (0..2) |_| {
        const image = try ui.image(cx, g_textures[2], .{ .width = .fixed(640), .height = .fixed(480) });
        try g_scroll.content.appendChild(cx.allocator, image);
    }
    try root.appendChild(cx.allocator, g_scroll.container);
    g_glass = try ui.widgets.GlassBox(.{ .width = 320, .height = 64, .corner_radius = 32, .padding = ui.Padding.all(0), .interactive = true }).mountWithState(scope, cx);
    g_glass.box.style.position = .absolute;
    g_glass.box.meta.ownership.meta.test_id = "glass.reference";
    g_glass.box.addBeforeRender(beforeRender);
    g_foreground = try ui.image(cx, g_foreground_textures[0], .{ .width = .fill(), .height = .fill() });
    g_foreground.style.display = .none;
    try g_glass.body.appendChild(cx.allocator, g_foreground);
    try root.appendChild(cx.allocator, g_glass.box);
    g_drag = try ui.interaction.drag.Binding.attach(scope, cx, g_glass.body, .{ .activation_distance = 0 }, onDrag, @ptrCast(g_glass.state));
    g_drag_handler = g_glass.body.behavior.events.on_event;
    g_glass.body.behavior.events.on_event = null;
    g_drag.setEnabled(false);
    return root;
}
fn onDrag(event: ui.interaction.drag.Event, _: *anyopaque) void {
    if (event.phase == .cancel) return;
    if (event.phase == .move or event.phase == .start) g_drag_moves += 1;
    const ext = g_glass.box.style.ensureExtFallible(g_app.allocator) catch return;
    ext.inset = .{ .left = .{ .px = 160 + event.delta.x }, .top = .{ .px = 208 + event.delta.y } };
    g_glass.box.markLayoutDirty();
    g_glass.box.markRenderDirty();
}
fn setup(index: usize) !void {
    g_motion = false;
    g_clock_trace_morph_start_ms = 0;
    g_app.cx.cancelPointerInteractions(.disabled);
    g_drag.setEnabled(false);
    g_glass.body.behavior.events.on_event = null;
    g_glass.body.markInteractionDirty();
    // End the previous fixture's hover through the public input path before
    // resetting component state. Reusing the same position would otherwise
    // retain Cx's hovered node and suppress the next mouse-enter transition.
    g_app.cx.handleMouseMove(60, 60);
    g_drag_moves = 0;
    g_tune = .{};
    g_background.style.display = .flex;
    g_scroll.container.style.display = .none;
    g_scroll.state.scroll_y = 0;
    g_scroll.state.bonus_y = 0;
    g_scroll.content.style.translate_y = 0;
    g_background.markLayoutDirty();
    g_scroll.container.markLayoutDirty();
    const s = g_scenes[index];
    g_foreground.style.display = if (s.foreground != null) .flex else .none;
    if (s.foreground) |foreground| for (foreground_names, 0..) |name, texture_index| {
        if (std.mem.eql(u8, foreground, name)) g_foreground.setImage(.{ .texture_id = g_foreground_textures[texture_index] });
    };
    g_foreground.markLayoutDirty();
    var mode: usize = 0;
    for (background_names, 0..) |name, texture_index| if (std.mem.eql(u8, s.background, name)) {
        mode = texture_index;
        break;
    };
    const dark_scheme = if (s.scheme) |scheme| std.mem.eql(u8, scheme, "dark") else mode == 1;
    const tokens = if (dark_scheme) &ui.theme.dark else &ui.theme.light;
    g_app.cx.setTheme(tokens);
    g_background.setImage(.{ .texture_id = g_scene_textures[index] });
    g_background.markRenderDirty();
    g_glass.box.style.width = .fixed(s.w);
    g_glass.box.style.height = .fixed(s.h);
    (try g_glass.box.style.ensureExtFallible(g_app.allocator)).inset = .{ .left = .{ .px = s.x }, .top = .{ .px = s.y } };
    const state = g_glass.state;
    state.interactive = false;
    state.hovered = false;
    state.pressed = false;
    state.glass_boost = 0;
    state.boost_event_pending = false;
    state.morph = null;
    state.theme_tokens = tokens;
    state.radius = s.radius;
    state.variant = if (std.mem.eql(u8, s.variant, "clear")) .clear else .regular;
    state.profile = if (s.idiom) |i| (if (std.mem.eql(u8, i, "ios")) &Glass.profile.ios else &Glass.profile.macos) else &Glass.profile.macos;
    state.tint_override = Glass.effectiveTintColor(if (s.tint) |t| ui.Color.rgba(t[0], t[1], t[2], s.tint_alpha orelse 255) else null);
    state.live_luminance = null;
    // A new scene is a freshly created effect: it starts in the appearance family
    // (native_family_fresh.swift: light appearance -> light family, dark -> dark family).
    state.live_luminance_srgb = null;
    ui.widgets.glass_box.glassSetFamilyImmediate(state, dark_scheme and Glass.adaptsFamily(&state.profile.family, state.variant, state.tint_override != null));
    // Drop the previous scene's luminance readback for this glass, otherwise the
    // stale dark reading re-enters the dark family before the new backdrop is read.
    for (&g_app.renderer.persistent_gpu.luminance_slots) |*slot| if (slot.key == state.surface.id) {
        slot.value = null;
        slot.value_srgb = null;
        // In-flight staging copies still hold the previous scene's backdrop.
        slot.cur_pending = false;
        slot.prev_pending = false;
    };
    state.last_style = null;
    g_glass.box.markSizingDirty();
    g_glass.box.markLayoutDirty();
    state.surface.markRenderDirty();
}
fn beforeRender(_: *ui.Node) void {
    // Registered after the production GlassBox hook: read its updated style
    // geometry without changing animation progress, layout, or frame content.
    traceMotionPose();
    const ext = g_glass.state.surface.style.ext orelse return;
    var glass = ext.glass orelse return;
    inline for (@import("zenit_reflection").fields(Tune)) |field| {
        if (comptime !std.mem.eql(u8, field.name, "tint_alpha") and !std.mem.eql(u8, field.name, "tint")) {
            if (@field(g_tune, field.name)) |value| @field(glass, field.name) = value;
        }
    }
    if (g_tune.tint_alpha) |alpha| if (glass.glass_tint) |*tint| {
        tint.a = alpha;
    };
    if (g_tune.tint) |tint| glass.glass_tint = ui.Color.rgba(tint[0], tint[1], tint[2], tint[3]);
    if (!std.meta.eql(glass, ext.glass.?)) {
        ext.glass = glass;
        g_glass.state.surface.markRenderDirty();
    }
}
fn route(path: []const u8, body: []const u8, out: []u8) ?[]const u8 {
    if (std.mem.eql(u8, path, "/glass/motion/setup")) {
        const p = std.json.parseFromSlice(struct { action: []const u8 }, g_app.allocator, body, .{}) catch return "{\"ok\":false}";
        defer p.deinit();
        const action = p.value.action;
        const is_scroll = std.mem.eql(u8, action, "scroll");
        const is_drag = std.mem.eql(u8, action, "drag");
        if (!is_scroll and !is_drag and !std.mem.eql(u8, action, "morph") and !std.mem.eql(u8, action, "hover_press_release")) return "{\"ok\":false}";
        const scene_id = if (std.mem.eql(u8, action, "hover_press_release")) "content-regular-panel" else "mixed-regular-capsule";
        for (g_scenes, 0..) |s, index| if (std.mem.eql(u8, s.id, scene_id)) {
            setup(index) catch return "{\"ok\":false}";
            break;
        };
        g_motion = true;
        g_background.setImage(.{ .texture_id = g_textures[2] });
        g_glass.state.interactive = true;
        g_drag.setEnabled(is_drag);
        g_glass.body.behavior.events.on_event = if (is_drag) g_drag_handler else null;
        g_glass.body.markInteractionDirty();
        g_background.style.display = if (is_scroll) .none else .flex;
        g_scroll.container.style.display = if (is_scroll) .flex else .none;
        g_background.markLayoutDirty();
        g_scroll.container.markLayoutDirty();
        g_glass.box.markRenderDirty();
        return "{\"ok\":true}";
    }
    if (std.mem.eql(u8, path, "/glass/motion/event")) {
        if (!g_motion or !std.meta.eql(g_tune, Tune{})) return "{\"ok\":false}";
        const Event = struct { name: []const u8, x: f32 = 320, y: f32 = 240, dy: f32 = -8 };
        const p = std.json.parseFromSlice(Event, g_app.allocator, body, .{}) catch return "{\"ok\":false}";
        defer p.deinit();
        const e = p.value;
        const time: f64 = @as(f64, @floatFromInt(std.Io.Clock.awake.now(g_app.cx.io).nanoseconds)) / 1e9;
        const clock_trace_enabled = metal_glass_clock_trace_enabled();
        const event_host_time = if (clock_trace_enabled) metal_glass_clock_trace_host_time() else 0;
        const event_clock_ms = if (clock_trace_enabled) g_app.cx.eventTimeMs() else 0;
        if (std.mem.eql(u8, e.name, "morph")) {
            Glass.glassMorphTo(g_glass.state, .{ .x = 200, .y = 160, .w = 240, .h = 160, .frames = 18 });
            if (clock_trace_enabled) if (g_glass.state.morph) |m| {
                g_clock_trace_morph_start_ms = m.start_time_ms;
            };
        } else if (std.mem.eql(u8, e.name, "move")) {
            g_app.cx.handleMouseMove(e.x, e.y);
        } else if (std.mem.eql(u8, e.name, "down")) {
            g_app.cx.handleMouseDown(e.x, e.y, .{});
        } else if (std.mem.eql(u8, e.name, "up")) {
            g_app.cx.handleMouseUp(e.x, e.y);
        } else if (std.mem.eql(u8, e.name, "scroll")) {
            g_app.cx.handleScroll(.{ .x = e.x, .y = e.y, .dx = 0, .dy = e.dy });
        } else return "{\"ok\":false}";
        if (clock_trace_enabled) {
            g_clock_trace_event += 1;
            emitClockTrace("{{\"kind\":\"event\",\"event\":{d},\"name\":\"{s}\",\"host_time\":{d:.9},\"unix_time\":{d:.9},\"event_time_ms\":{d:.6},\"previous_frame_time_ms\":{d:.6},\"previous_frame_dt_ms\":{d:.6},\"next_frame\":{d},\"morph_start_ms\":{d:.6},\"dispatch_end_time\":{d:.9}}}", .{
                g_clock_trace_event,    e.name,               event_host_time,                time,                         event_clock_ms,
                g_app.cx.frame_time_ms, g_app.cx.frame_dt_ms, g_app.renderer.frame_count + 1, g_clock_trace_morph_start_ms, metal_glass_clock_trace_host_time(),
            });
        }
        return std.fmt.bufPrint(out, "{{\"ok\":true,\"unix_time\":{d:.9},\"hovered\":{},\"pressed\":{},\"drag_moves\":{d},\"scroll_y\":{d}}}", .{ time, g_glass.state.hovered, g_glass.state.pressed, g_drag_moves, g_scroll.state.scroll_y }) catch "{\"ok\":false}";
    }
    if (std.mem.eql(u8, path, "/glass/state")) {
        return std.fmt.bufPrint(out, "{{\"luminance\":{d},\"luminance_srgb\":{d},\"family_dark\":{},\"target_luminance\":{d},\"needs_frame\":{},\"frame_count\":{d},\"glass_pipeline_failed\":{},\"blur_pipeline_failed\":{},\"calibration_active\":{}}}", .{
            g_glass.state.live_luminance orelse -1,
            g_glass.state.live_luminance_srgb orelse -1,
            g_glass.state.family_dark,
            g_app.cx.backdrop_luminance orelse -1,
            g_app.cx.wantsFrame(),
            g_app.renderer.frame_count,
            g_app.renderer.persistent_gpu.glass_pipeline_failed,
            g_app.renderer.persistent_gpu.blur_pipeline_failed,
            !std.meta.eql(g_tune, Tune{}),
        }) catch "{}";
    }
    if (std.mem.eql(u8, path, "/glass/tune")) {
        const p = std.json.parseFromSlice(Tune, g_app.allocator, body, .{}) catch return "{\"ok\":false}";
        defer p.deinit();
        g_tune = p.value;
        g_glass.state.last_style = null;
        g_glass.state.surface.markRenderDirty();
        g_glass.box.markRenderDirty();
        return "{\"ok\":true}";
    }
    if (!std.mem.eql(u8, path, "/glass/setup")) return null;
    const p = std.json.parseFromSlice(struct { index: usize }, g_app.allocator, body, .{ .ignore_unknown_fields = true }) catch return "{\"ok\":false}";
    defer p.deinit();
    if (p.value.index >= g_scenes.len) return "{\"ok\":false}";
    setup(p.value.index) catch return "{\"ok\":false}";
    return std.fmt.bufPrint(out, "{{\"ok\":true,\"case\":\"{s}\"}}", .{g_scenes[p.value.index].id}) catch "{\"ok\":false}";
}
pub fn main(init: std.process.Init) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const assets = try @import("zenit_environment").getOwned(allocator, "ZENIT_GLASS_FIXTURES");
    defer allocator.free(assets);
    const scenes_path = try std.fs.path.join(allocator, &.{ assets, "scenes.json" });
    defer allocator.free(scenes_path);
    const json = try std.Io.Dir.cwd().readFileAlloc(init.io, scenes_path, allocator, .limited(1024 * 1024));
    defer allocator.free(json);
    const parsed = try std.json.parseFromSlice([]Scene, allocator, json, .{});
    defer parsed.deinit();
    g_scenes = parsed.value;
    var application = runtime.MultiWindowApp.init(allocator, .{});
    defer application.deinit();
    g_app = try application.createWindow(.{ .io = init.io, .window = .{ .width = 640, .height = 480, .title = "Glass Reference Probe" }, .idle_skip_frames = true });
    for (background_names, 0..) |name, i| {
        const path = try std.fmt.allocPrint(allocator, "{s}/{s}.rgba", .{ assets, name });
        defer allocator.free(path);
        const rgba = try std.Io.Dir.cwd().readFileAlloc(init.io, path, allocator, .limited(1280 * 960 * 4 + 1));
        defer allocator.free(rgba);
        g_textures[i] = try g_app.renderer.image_renderer.loadTexture(1280, 960, rgba);
    }
    // Diagnostic backgrounds must use their actual pixels, never silently
    // fall back to the first built-in texture when a scene name is unfamiliar.
    g_scene_textures = try allocator.alloc(u32, g_scenes.len);
    defer allocator.free(g_scene_textures);
    for (g_scenes, 0..) |scene, i| {
        var known = false;
        for (background_names, 0..) |name, j| {
            if (std.mem.eql(u8, scene.background, name)) {
                g_scene_textures[i] = g_textures[j];
                known = true;
                break;
            }
        }
        if (known) continue;
        const path = try std.fmt.allocPrint(allocator, "{s}/{s}.rgba", .{ assets, scene.background });
        defer allocator.free(path);
        const rgba = try std.Io.Dir.cwd().readFileAlloc(init.io, path, allocator, .limited(1280 * 960 * 4 + 1));
        defer allocator.free(rgba);
        if (rgba.len != 1280 * 960 * 4) return error.InvalidBackgroundDimensions;
        g_scene_textures[i] = try g_app.renderer.image_renderer.loadTexture(1280, 960, rgba);
    }
    for (foreground_names, 0..) |name, i| {
        const path = try std.fmt.allocPrint(allocator, "{s}/{s}.rgba", .{ assets, name });
        defer allocator.free(path);
        const w: u32 = if (i == 2) 840 else 480;
        const h: u32 = if (i == 2) 88 else 208;
        const rgba = try std.Io.Dir.cwd().readFileAlloc(init.io, path, allocator, .limited(w * h * 4 + 1));
        defer allocator.free(rgba);
        g_foreground_textures[i] = try g_app.renderer.image_renderer.loadTexture(w, h, rgba);
    }
    try g_app.mount(mount);
    try setup(0);
    runtime.setTestRouteHandler(route);
    const action: std.posix.Sigaction = .{ .handler = .{ .handler = terminate }, .mask = std.posix.sigemptyset(), .flags = 0 };
    std.posix.sigaction(std.posix.SIG.TERM, &action, null);
    std.posix.sigaction(std.posix.SIG.INT, &action, null);
    while (try application.tick()) {
        if (g_quit.load(.acquire)) {
            application.quit();
            break;
        }
    }
}
