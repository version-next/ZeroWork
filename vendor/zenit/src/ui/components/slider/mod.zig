/// Slider: range selector.
///
/// Features:
/// - min/max/step range
/// - drag + track click
/// - keyboard (ArrowLeft/Right +/-step, Home/End)
/// - optional value display
/// - Signal-first: `value: Model(f32)`; `disabled` / `haptic_*` are Source.
///   User input is snapped per step, clamped to [min, max], then proposed; on_change fires after
///   landing
const std = @import("std");
const Allocator = std.mem.Allocator;
const core = @import("../../core.zig");
const Cx = core.Cx;
const Node = core.Node;
const box = core.box;
const Color = core.Color;
const reactive = @import("../../reactive.zig");
const Scope = reactive.Scope;
const Signal = reactive.Signal;
const Source = reactive.Source;
const Model = reactive.Model;
const Handler = core.Handler;
const recipe_mod = @import("../../recipe.zig");
const hooks = @import("../../hooks.zig");
const events = @import("../../events.zig");
const Event = events.Event;
const EventResult = events.EventResult;
const KeyCode = events.KeyCode;
const view = @import("../../view.zig");

const Modifiers = events.Modifiers;
pub const HapticFeedbackPattern = @import("system_sdk").HapticFeedbackPattern;

/// Slider properties
// Style layer extracted to styles.zig
const styles = @import("styles.zig");
const trackStyle = styles.trackStyle;
const fillStyle = styles.fillStyle;
const thumbStyle = styles.thumbStyle;

/// A tick mark on the track (SliderProps.marks): a dot at `value`, and when `label` is not empty a
/// line of text under it. test_id / label_test_id go on the dot / the text node.
pub const SliderMark = struct {
    value: f32,
    label: []const u8 = "",
    test_id: ?[]const u8 = null,
    label_test_id: ?[]const u8 = null,
};

/// Slider paint. default: light thumb face with an accent outline over the range_track track.
/// stepped: a solid accent thumb (the fill's color, no face, no outline, no shadow) over a
/// translucent fg-tertiary track, accent mark dots; disabled thumb / fill / dots in fg-tertiary.
pub const SliderLook = enum { default, stepped };

pub const SliderProps = struct {
    label_text: ?[]const u8 = null,
    min: f32 = 0,
    max: f32 = 100,
    /// Positive values snap to discrete steps. Zero disables snapping.
    step: f32 = 1,
    /// Current value: `f32` uncontrolled initial; `*Signal(f32)` controlled (interaction writes
    /// directly); `ui.split` intercepts.
    /// External out-of-range values clamped to [min, max] for display (no write-back).
    value: Model(f32) = .{ .local = 0 },
    disabled: Source(bool) = .{ .value = false },
    /// Opt in to native feedback when pointer input changes a snapped value.
    /// Applications may bind this to their user's preference.
    haptic_feedback: Source(bool) = .{ .value = false },
    /// Native semantic pattern, not a weak/medium/strong intensity scale.
    haptic_pattern: Source(HapticFeedbackPattern) = .{ .value = .alignment },
    width: f32 = 200,
    track_height: f32 = 4,
    thumb_size: f32 = 16,
    show_value: bool = false,
    /// Called after user changes value and lands (landed value); each snapped value during drag
    on_change: ?Handler(f32) = null,
    /// test_id set on track node (for E2E testing)
    test_id: ?[]const u8 = null,
    /// Tick marks drawn in the track area under the thumb (see SliderMark): a 4px dot each at the
    /// value's position (out-of-range values pinned to the ends), its label (when not empty) as
    /// 9px fg-tertiary text centered under it. Neither is hit-testable (a click lands on the
    /// track area as before). A source: dots and labels follow it (count, position, text).
    /// Empty (default) adds no node.
    marks: Source([]const SliderMark) = .{ .value = &.{} },
    /// false hides the thumb (display none); track, fill and marks stay.
    thumb_visible: Source(bool) = .{ .value = true },
    /// Paint (see SliderLook); follows theme switches like the default.
    look: SliderLook = .default,
};

/// Slider runtime (scope-owned). View = f(value, disabled, hover), applied by effect;
/// interaction only via `propose`.
pub const SliderRuntime = struct {
    value: reactive.Bound(f32),
    disabled: Source(bool),
    marks: Source([]const SliderMark),
    thumb_visible: Source(bool),
    look: SliderLook,
    haptic_feedback: Source(bool),
    haptic_pattern: Source(HapticFeedbackPattern),
    on_change: ?Handler(f32),
    min: f32,
    max: f32,
    step: f32,
    thumb_size: f32,
    accent: Color,
    accent_hover: Color,
    tokens: *const core.ThemeTokens,
    /// Allocator of the mark lists (the slider scope's, which frees them with the runtime).
    scope_allocator: Allocator,
    /// The view reads it: a theme switch recolors the track, fill, thumb and value text.
    theme: *Signal(*const core.ThemeTokens),
    hovered: *Signal(bool),
    dragging: bool = false,
    /// Currently displayed value (data source value clamped to [min, max])
    shown: f32 = 0,
    is_disabled: bool = false,
    /// Thumb display last applied (thumb_visible).
    thumb_shown: bool = true,
    /// Mark dots (in track_area, before the thumb) and the labels of marks with text (after it),
    /// in mark order; rebuilt when `marks` changes.
    mark_dots: std.ArrayList(*Node) = .empty,
    mark_labels: std.ArrayList(*Node) = .empty,
    /// The marks mount built; the marks effect's first run skips the rebuild when it reads the
    /// same list.
    marks_at_mount: ?[]const SliderMark = null,
    track_node: *Node,
    fill_node: *Node,
    thumb_node: *Node,
    track_area_node: *Node,
    value_text_node: ?*Node = null,
    container_node: *Node,
    cx: *Cx,

    fn ratio(self: *const SliderRuntime) f32 {
        if (self.max <= self.min) return 0;
        return std.math.clamp((self.shown - self.min) / (self.max - self.min), 0, 1);
    }

    /// Data source value -> display value: clamp out-of-range, treat NaN as min
    fn displayOf(self: *const SliderRuntime, v: f32) f32 {
        if (std.math.isNan(v)) return self.min;
        return std.math.clamp(v, self.min, self.max);
    }

    /// User input -> proposed value: clamp, snap per step, clamp again (snap may overshoot max)
    fn sanitize(self: *const SliderRuntime, raw: f32) f32 {
        const clamped = self.displayOf(raw);
        const stepped = if (self.step > 0 and std.math.isFinite(self.step))
            self.min + @round((clamped - self.min) / self.step) * self.step
        else
            clamped;
        return std.math.clamp(stepped, self.min, self.max);
    }

    fn view(self: *SliderRuntime, comptime tracked: bool) !void {
        const v = self.displayOf(self.value.readAs(tracked));
        const dis = self.disabled.read(tracked);
        const hov = if (tracked) self.hovered.get() else self.hovered.peek();
        const tokens = if (tracked) self.theme.get() else self.theme.peek();
        const thumb_visible = self.thumb_visible.read(tracked);
        if (thumb_visible != self.thumb_shown) {
            self.thumb_shown = thumb_visible;
            self.thumb_node.setDisplay(if (thumb_visible) .flex else .none);
        }
        if (tokens != self.tokens) self.applyTheme(tokens);
        if (dis != self.is_disabled) {
            self.is_disabled = dis;
            self.applyDisabled();
        }
        // When disabled, hover highlight not shown; a drag keeps it while the pointer leaves
        // the track. Color transitions via border-color.
        self.thumb_node.setBorderColor(if (dis) self.tokens.tokens.color.range_disabled else if (self.dragging) self.tokens.tokens.color.range_drag else if (hov) self.accent_hover else self.accent);
        if (v != self.shown) {
            self.shown = v;
            try self.updateVisuals();
        }
    }

    /// Theme switch: everything painted from mount-time tokens is re-resolved, as a fresh
    /// mount under the new theme would paint it.
    fn applyTheme(self: *SliderRuntime, t: *const core.ThemeTokens) void {
        self.tokens = t;
        self.accent = t.tokens.color.range_fill;
        self.accent_hover = t.tokens.color.range_hover;
        self.track_node.setBackground(styles.trackBackground(self.look, t));
        if (self.value_text_node) |text| text.setTextColor(t.tokens.color.fg_secondary);
        for (self.mark_labels.items) |label| label.setTextColor(styles.markLabelColor(t));
        self.applyDisabled();
    }

    fn markPercent(self: *const SliderRuntime, value: f32) f32 {
        if (self.max <= self.min or std.math.isNan(value)) return 0;
        return std.math.clamp((value - self.min) / (self.max - self.min), 0, 1) * 100;
    }

    /// Drop the current mark nodes and build `marks` in their place: dots before the thumb (it
    /// covers them), labels after it.
    fn syncMarks(self: *SliderRuntime, marks: []const SliderMark) !void {
        const cx = self.cx;
        const area = self.track_area_node;
        for (self.mark_dots.items) |dot| {
            area.removeChild(dot);
            cx.freeNode(dot);
        }
        self.mark_dots.clearRetainingCapacity();
        for (self.mark_labels.items) |label| {
            area.removeChild(label);
            cx.freeNode(label);
        }
        self.mark_labels.clearRetainingCapacity();
        const alloc = cx.allocator;
        const list_alloc = self.listAllocator();
        const dot_color = styles.fillBackground(self.look, self.is_disabled, self.accent, self.tokens);
        for (marks) |mark| {
            const percent = self.markPercent(mark.value);
            try self.mark_dots.ensureUnusedCapacity(list_alloc, 1);
            const dot = try box(cx, styles.markDotStyle(percent, dot_color), .{});
            dot.setHitTestVisible(false);
            dot.meta.ownership.meta.test_id = mark.test_id;
            area.insertChildBefore(alloc, dot, self.thumb_node) catch |err| {
                cx.freeNode(dot);
                return err;
            };
            self.mark_dots.appendAssumeCapacity(dot);
            if (mark.label.len == 0) continue;
            try self.mark_labels.ensureUnusedCapacity(list_alloc, 1);
            const label = try core.text(cx, "", styles.markLabelText(self.tokens));
            label.setTextContent(alloc, mark.label) catch |err| {
                cx.freeNode(label);
                return err;
            };
            label.setStyleInlineFallible(alloc, styles.markLabelBox(percent)) catch |err| {
                cx.freeNode(label);
                return err;
            };
            label.setHitTestVisible(false);
            label.meta.ownership.meta.test_id = mark.label_test_id;
            area.appendChild(alloc, label) catch |err| {
                cx.freeNode(label);
                return err;
            };
            self.mark_labels.appendAssumeCapacity(label);
        }
        area.markLayoutDirty();
    }

    fn listAllocator(self: *const SliderRuntime) Allocator {
        return self.scope_allocator;
    }

    fn marksEffect(self: *SliderRuntime) void {
        const marks = self.marks.read(true);
        if (self.marks_at_mount) |built| {
            self.marks_at_mount = null;
            if (built.ptr == marks.ptr and built.len == marks.len) return;
        }
        self.syncMarks(marks) catch |err| std.log.err("[Slider] marks update failed: {}", .{err});
    }

    fn viewEffect(self: *SliderRuntime) void {
        self.view(true) catch |err| std.log.err("[Slider] update failed: {}", .{err});
    }

    fn applyDisabled(self: *SliderRuntime) void {
        const dis = self.is_disabled;
        const t = self.tokens;
        self.container_node.setFocusable(!dis);
        self.container_node.style.cursor = if (dis) .not_allowed else .default;
        self.thumb_node.style.cursor = if (dis) .not_allowed else .pointer;
        if (self.container_node.behavior.interaction.a11y) |*a| a.disabled = dis;
        self.fill_node.setBackground(styles.fillBackground(self.look, dis, self.accent, t));
        self.thumb_node.setBackground(styles.thumbBackground(self.look, dis, self.accent, t));
        const dot_color = styles.fillBackground(self.look, dis, self.accent, t);
        for (self.mark_dots.items) |dot| dot.setBackground(dot_color);
        if (dis and self.dragging) {
            self.dragging = false;
            if (sliderOwnsCapture(self)) self.cx.releasePointerCapture();
        }
        self.container_node.markRenderDirty();
    }

    fn updateVisuals(self: *SliderRuntime) !void {
        // a11y value must track value, else VoiceOver forever plays mount-time initial.
        if (self.container_node.behavior.interaction.a11y) |*a| {
            a.value_now = self.shown;
            a.value_min = self.min;
            a.value_max = self.max;
            if (a.value_range) |*range| {
                range.now = self.shown;
                range.min = self.min;
                range.max = self.max;
                range.small_change = self.step;
            }
        }

        const r = self.ratio();
        const tr = self.track_node.rectFromWorldOrFallback();
        const thumb_offset = r * tr.w - self.thumb_size / 2;

        self.fill_node.style.width = .{ .percent = r * 100 };
        self.fill_node.markSizingDirty();

        // thumb positioned via translate_x: pure composite offset, drag zero relayout.
        self.thumb_node.setTranslateX(thumb_offset);

        if (self.value_text_node) |vt| {
            var buf: [64]u8 = undefined;
            const content = std.fmt.bufPrint(&buf, "{d:.1}", .{self.shown}) catch unreachable; // f32 {d:.1} longest < 64
            try vt.setTextContent(self.cx.allocator, content);
            vt.markRenderDirty();
        }
    }

    /// User input: snap then propose; landing gives haptic + on_change.
    /// on_change may destroy this component: it must be last step, no self access after.
    /// Disabled state checked by each entry (mouse_down / keyboard / a11y reject, cancel in-flight
    /// drag on disable).
    fn propose(self: *SliderRuntime, raw: f32, pointer_driven: bool) void {
        const landed = self.value.commit(self.sanitize(raw)) orelse return;
        // Once per landed snapped value, never per pointer sample or skipped intermediate step.
        // Programmatic / keyboard / a11y value changes give no haptic.
        if (pointer_driven and self.step > 0 and std.math.isFinite(self.step) and self.haptic_feedback.peek()) {
            if (self.cx.system_sdk) |sdk| sdk.performHapticFeedback(self.haptic_pattern.peek()) catch {};
        }
        if (self.on_change) |h| h.call(landed);
    }

    /// Arrow key step: continuous slider (step 0) uses 1% of range, else keyboard & screenreader
    /// users cannot adjust
    fn keyStep(self: *const SliderRuntime) f32 {
        if (self.step > 0 and std.math.isFinite(self.step)) return self.step;
        return (self.max - self.min) / 100;
    }

    fn setFromScreenX(self: *SliderRuntime, screen_x: f32) void {
        const track_global = self.track_node.globalRect();
        if (track_global.w <= 0) return;
        const r = std.math.clamp((screen_x - track_global.x) / track_global.w, 0, 1);
        self.propose(self.min + r * (self.max - self.min), true);
    }
};

/// Return true means this control handled request (caller focuses it); proposal acceptance decided
/// by data source.
fn setA11ySliderValue(context: *anyopaque, value: f32) bool {
    const rt: *SliderRuntime = @ptrCast(@alignCast(context));
    if (rt.is_disabled) return false;
    rt.propose(value, false);
    return true;
}

/// Create Slider: `W.Slider(.{ .min = 0, .max = 10, .value = volume })`
pub fn Slider(props: anytype) SliderBuilder {
    return .{ .props = reactive.props.coerce(SliderProps, props) };
}

/// SliderBuilder.mount result
pub const SliderResult = struct {
    wrapper: *Node,
    /// Value signal (`ui.split` when null)
    value: ?*Signal(f32),
    /// `ui.view` entry (see src/ui/view_parts.zig).
    pub fn viewParts(self: SliderResult) core.ViewParts {
        return .{ .root = self.wrapper };
    }
};

pub const SliderBuilder = struct {
    props: SliderProps,

    pub fn mount(self: SliderBuilder, scope: *Scope, cx: *Cx) !SliderResult {
        cx.owner.enterMount();
        defer cx.owner.exitMount();
        const my_scope = try scope.childScope();
        var scope_bound = false;
        errdefer if (!scope_bound) my_scope.dispose();
        const allocator = cx.allocator;
        const t = cx.tokens;
        // Normalize range when min > max: std.math.clamp asserts on min > max
        const p = blk: {
            var np = self.props;
            if (np.min > np.max) std.mem.swap(f32, &np.min, &np.max);
            break :blk np;
        };
        reactive.checkBorrow(my_scope, p.disabled);
        reactive.checkBorrow(my_scope, p.marks);
        reactive.checkBorrow(my_scope, p.thumb_visible);
        reactive.checkBorrow(my_scope, p.haptic_feedback);
        reactive.checkBorrow(my_scope, p.haptic_pattern);
        const value = try reactive.resolveModel(f32, my_scope, p.value);
        const initially_disabled = p.disabled.read(false);
        const accent = t.tokens.color.range_fill;

        // Outer container: track region (track + fill + thumb) + optional value display
        const Parts = struct { track_area: *Node = undefined, track: *Node = undefined, fill: *Node = undefined, thumb: *Node = undefined, text: ?*Node = null };
        var parts: Parts = .{};
        const container = try view.render(my_scope, cx, view.box(.{
            .style = core.BoxStyle{
                .width = .{ .px = p.width },
                .height = .{ .fit = .{} },
                .direction = .row,
                .align_items = .center,
                .gap = 8,
            },
            // value_now/min/max projected into a11y tree so VoiceOver can speak 'value, range 0 to
            // 100'
            .a11y = .{
                .role = .slider,
                .label = p.label_text,
                .value_min = p.min,
                .value_max = p.max,
                .orientation = .horizontal,
            },
        }, .{
            // Track container (relative positioned, contains track + thumb)
            view.capture(&parts.track_area, view.box(.{ .style = core.BoxStyle{
                .width = .{ .grow = .{} },
                .height = .{ .px = p.thumb_size },
                .direction = .column,
                .justify = .center,
                .position = .relative,
            } }, .{
                // Track; fill width and color applied by view
                view.capture(&parts.track, view.box(.{
                    .style = .{ trackStyle(p, t), .{ .overflow_hidden = true } },
                    .test_id = p.test_id,
                }, view.capture(&parts.fill, view.box(.{ .style = fillStyle(p, accent, 0) }, {})))),
                // Thumb: border color transitions in normal / hover / disabled
                view.capture(&parts.thumb, view.box(.{ .style = .{ thumbStyle(p, false, accent, t), .{ .translate_y = 0, .cursor = .pointer } } }, {})),
            })),
            // Optional value display (content written by view)
            if (p.show_value) view.capture(&parts.text, view.attrs(.{ .style = core.BoxStyle{ .width = .{ .fit = .{ .min = 30 } } } }, view.text(.{ .style = core.TextStyle{
                .color = t.tokens.color.fg_secondary,
                .font_size = t.tokens.font_size.sm,
            } }, ""))) else null,
        }));
        // sweep: container guards to return
        errdefer cx.freeNode(container);
        container.meta.ownership.meta.component_name = "Slider";
        try core.bindScopeToNode(my_scope, container);
        scope_bound = true;
        const track_area = parts.track_area;
        const track = parts.track;
        const fill = parts.fill;
        const thumb = parts.thumb;
        try thumb.applyTransition(allocator, &comptime recipe_mod.transition("border-color 120ms ease-out"));

        const hovered = try hooks.useHover(my_scope, track_area);
        const theme_signal = try cx.themeSignal();

        const rt = try my_scope.allocator.create(SliderRuntime);
        rt.* = .{
            .value = value,
            .disabled = p.disabled,
            .marks = p.marks,
            .thumb_visible = p.thumb_visible,
            .look = p.look,
            .haptic_feedback = p.haptic_feedback,
            .haptic_pattern = p.haptic_pattern,
            .on_change = p.on_change,
            .min = p.min,
            .max = p.max,
            .step = p.step,
            .thumb_size = p.thumb_size,
            .accent = accent,
            .accent_hover = t.tokens.color.range_hover,
            .tokens = t,
            .scope_allocator = my_scope.allocator,
            .theme = theme_signal,
            .hovered = hovered,
            // Not equal to any display value: first view must apply
            .shown = std.math.nan(f32),
            .track_node = track,
            .fill_node = fill,
            .thumb_node = thumb,
            .track_area_node = track_area,
            .container_node = container,
            .cx = cx,
        };
        try my_scope.adoptResource(@ptrCast(rt), struct {
            fn cleanup(ptr: *anyopaque, alloc: Allocator) void {
                const runtime: *SliderRuntime = @ptrCast(@alignCast(ptr));
                runtime.mark_dots.deinit(alloc);
                runtime.mark_labels.deinit(alloc);
                alloc.destroy(runtime);
            }
        }.cleanup);
        if (container.behavior.interaction.a11y) |*a11y| {
            a11y.value_range = .{
                .small_change = p.step,
                .now = 0,
                .min = p.min,
                .max = p.max,
                .context = rt,
                .set_value = setA11ySliderValue,
            };
        }

        rt.value_text_node = parts.text;

        // Interaction always hooked, disabled determined at runtime (disabled can be dynamic)
        track_area.behavior.events.event_context = @ptrCast(rt);
        track_area.behavior.events.on_event = sliderEventHandler;
        track_area.on_capture_lost = sliderCaptureLost;
        container.behavior.events.on_key_down = sliderKeyHandler;
        container.behavior.events.key_context = @ptrCast(rt);

        // on_before_render: fix thumb position after layout
        track_area.meta.per_frame.hooks.before_render.main = sliderBeforeRender;

        // First apply view: is_disabled negated first, ensure disabled state applied once
        rt.is_disabled = !initially_disabled;
        try rt.view(false);
        // value is Model: local also signal, interaction changes it, must have effect
        try my_scope.createEffect(rt, SliderRuntime.viewEffect);
        // Marks: built now (a failure fails the mount), then rebuilt when the source changes.
        const initial_marks = p.marks.read(false);
        if (initial_marks.len != 0) try rt.syncMarks(initial_marks);
        rt.marks_at_mount = initial_marks;
        try my_scope.createEffect(rt, SliderRuntime.marksEffect);

        return .{ .wrapper = container, .value = value.asSignal() };
    }
};

// ========== Internal helpers ==========

fn sliderBeforeRender(node: *Node) void {
    if (node.behavior.events.event_context) |ctx| {
        const rt: *SliderRuntime = @ptrCast(@alignCast(ctx));
        // Update thumb position after layout (first frame track_w changes from 0 to actual)
        const tr = rt.track_node.rectFromWorldOrFallback();
        if (tr.w > 0) {
            const offset = rt.ratio() * tr.w - rt.thumb_size / 2;
            rt.thumb_node.setTranslateX(offset);
        }
    }
}

fn sliderCaptureLost(node: *Node) void {
    const context = node.behavior.events.event_context orelse return;
    const rt: *SliderRuntime = @ptrCast(@alignCast(context));
    rt.dragging = false;
    rt.view(false) catch {};
}

fn sliderOwnsCapture(rt: *const SliderRuntime) bool {
    return rt.cx.node_registry.resolve(rt.cx.dispatcher.pointer_capture_handle, null) == rt.track_area_node;
}

fn sliderEventHandler(event: Event, context: ?*anyopaque) EventResult {
    if (context == null) return .ignored;
    const rt: *SliderRuntime = @ptrCast(@alignCast(context.?));

    switch (event) {
        .mouse_down => |e| {
            if (rt.is_disabled) return .ignored;
            const cx = rt.cx;
            const identity = cx.node_registry.handleFor(rt.track_area_node);
            rt.dragging = true;
            // Replacing capture invokes the previous owner's callback, which
            // may destroy this slider or transfer capture elsewhere.
            cx.setPointerCapture(rt.track_area_node);
            const live = cx.node_registry.resolve(identity, null) orelse return .stop;
            if (live.behavior.events.event_context != context or live.behavior.events.on_event != sliderEventHandler) return .stop;
            if (!sliderOwnsCapture(rt)) {
                rt.dragging = false;
                return .stop;
            }
            rt.view(false) catch {};
            rt.setFromScreenX(e.x);
            return .stop;
        },
        .mouse_move => |e| {
            if (rt.dragging and !sliderOwnsCapture(rt)) rt.dragging = false;
            if (rt.dragging) {
                rt.setFromScreenX(e.x);
                return .stop;
            }
        },
        .mouse_up => {
            if (rt.dragging) {
                rt.dragging = false;
                if (sliderOwnsCapture(rt)) rt.cx.releasePointerCapture();
                rt.view(false) catch {};
                return .stop;
            }
            return .ignored;
        },
        else => {},
    }
    return .ignored;
}

fn sliderKeyHandler(key: KeyCode, _: Modifiers, context: ?*anyopaque) EventResult {
    if (context == null) return .ignored;
    const rt: *SliderRuntime = @ptrCast(@alignCast(context.?));
    if (rt.is_disabled) return .ignored;

    switch (key) {
        .right => rt.propose(rt.shown + rt.keyStep(), false),
        .left => rt.propose(rt.shown - rt.keyStep(), false),
        .home => rt.propose(rt.min, false),
        .end => rt.propose(rt.max, false),
        else => return .ignored,
    }
    return .stop;
}

// ========== Tests ==========

fn runtimeOf(r: SliderResult) *SliderRuntime {
    // track_area is wrapper's first child, event_context is runtime
    return @ptrCast(@alignCast(r.wrapper.children.items[0].behavior.events.event_context.?));
}

test "Slider: basic structure" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 100 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const result = try Slider(.{
        .min = 0,
        .max = 100,
        .value = 50,
    }).mount(scope, ctx);

    try root.appendChild(std.testing.allocator, result.wrapper);
    try std.testing.expectEqual(@as(f32, 50), result.value.?.peek());
}

test "Slider: re-applying an unchanged thumb offset requests no frame" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(400, 100);
    try ctx.setTestFrameStep(16);
    ctx.caret_flip_host = true;
    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 100 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const result = try Slider(.{ .min = 0, .max = 100, .value = 30, .width = 220 }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.wrapper);
    var frames: usize = 0;
    while (ctx.wantsFrame() and frames < 60) : (frames += 1) {
        ctx.advanceFrameClock();
        ctx.layout();
        _ = ctx.render();
    }
    try std.testing.expect(!ctx.wantsFrame());
    // The before-render hook runs in every rendered frame and re-applies the thumb offset. With
    // the offset unchanged it must leave the tree clean: a dirty hit scene each frame advances
    // the scene epoch, and a live stationary pointer then re-resolves hover and requests the
    // next frame forever (glasslab rendered 120 fps idle).
    const Find = struct {
        fn hooked(n: *Node) ?*Node {
            if (n.meta.per_frame.hooks.before_render.main == sliderBeforeRender) return n;
            for (n.children.items) |c| if (hooked(c)) |f| return f;
            return null;
        }
    };
    const track_area = Find.hooked(result.wrapper).?;
    const rt: *SliderRuntime = @ptrCast(@alignCast(track_area.behavior.events.event_context.?));
    const before = rt.thumb_node.style.translate_x;
    try std.testing.expect(before != 0);
    sliderBeforeRender(track_area);
    try std.testing.expectEqual(before, rt.thumb_node.style.translate_x);
    try std.testing.expect(!ctx.wantsFrame());
}

test "Slider: min > max 时 mount 不 assert，区间被规范化" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 100 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const result = try Slider(.{ .min = 100, .max = 0, .value = 150 }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.wrapper);
    const rt = runtimeOf(result);
    try std.testing.expectEqual(@as(f32, 0), rt.min);
    try std.testing.expectEqual(@as(f32, 100), rt.max);
    // External out-of-range values clamped to range, not written back
    try std.testing.expectEqual(@as(f32, 100), rt.shown);
    try std.testing.expectEqual(@as(f32, 150), result.value.?.peek());
    rt.propose(-5, false);
    try std.testing.expectEqual(@as(f32, 0), result.value.?.peek());
}

test "Slider: user input is clamped before it is proposed" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 100 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const result = try Slider(.{
        .min = 0,
        .max = 100,
        .step = 10,
    }).mount(scope, ctx);

    try root.appendChild(std.testing.allocator, result.wrapper);

    runtimeOf(result).propose(150, false);
    try std.testing.expectEqual(@as(f32, 100), result.value.?.peek());

    runtimeOf(result).propose(-10, false);
    try std.testing.expectEqual(@as(f32, 0), result.value.?.peek());
}

test "Slider: step snapping" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 100 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const result = try Slider(.{
        .min = 0,
        .max = 100,
        .step = 10,
    }).mount(scope, ctx);

    try root.appendChild(std.testing.allocator, result.wrapper);

    runtimeOf(result).propose(37, false);
    try std.testing.expectEqual(@as(f32, 40), result.value.?.peek());
}

test "Slider: keyboard" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 100 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const result = try Slider(.{
        .min = 0,
        .max = 100,
        .step = 5,
        .value = 50,
    }).mount(scope, ctx);

    try root.appendChild(std.testing.allocator, result.wrapper);

    _ = sliderKeyHandler(.right, .{}, @ptrCast(runtimeOf(result)));
    try std.testing.expectEqual(@as(f32, 55), result.value.?.peek());

    _ = sliderKeyHandler(.left, .{}, @ptrCast(runtimeOf(result)));
    try std.testing.expectEqual(@as(f32, 50), result.value.?.peek());

    _ = sliderKeyHandler(.home, .{}, @ptrCast(runtimeOf(result)));
    try std.testing.expectEqual(@as(f32, 0), result.value.?.peek());

    _ = sliderKeyHandler(.end, .{}, @ptrCast(runtimeOf(result)));
    try std.testing.expectEqual(@as(f32, 100), result.value.?.peek());
}

test "Slider: show value" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 100 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const result = try Slider(.{
        .value = 75,
        .show_value = true,
    }).mount(scope, ctx);

    try root.appendChild(std.testing.allocator, result.wrapper);

    // container should have 2 children: track_area + value_text
    try std.testing.expectEqual(@as(usize, 2), result.wrapper.children.items.len);
    try std.testing.expect(runtimeOf(result).value_text_node != null);
}

test "Slider: render emits fill highlight" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(260, 48);

    const root = try box(ctx, .{
        .width = .{ .px = 260 },
        .height = .{ .px = 48 },
        .background = ctx.tokens.tokens.color.bg_primary,
    }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const result = try Slider(.{
        .value = 70,
        .width = 220,
    }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.wrapper);

    ctx.layout();
    _ = ctx.render();
    const commands = ctx.lowerForEncoderPaintTable();

    var saw_fill = false;
    for (commands) |cmd| if (cmd.isFillRect()) {
        const r = cmd;
        if (Color.eql(r.color.toColor(), ctx.tokens.tokens.color.accent) and r.geom.w > 100 and r.geom.h >= 4) {
            saw_fill = true;
        }
    };

    try std.testing.expect(saw_fill);
}

test "Slider: bound value follows external writes; user input reports the landed value" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const volume = try scope.createSignal(f32, 20);
    const Rec = struct {
        calls: u32 = 0,
        last: f32 = 0,
        fn changed(self: *@This(), v: f32) void {
            self.calls += 1;
            self.last = v;
        }
    };
    var rec = Rec{};
    const result = try Slider(.{ .min = 0, .max = 100, .step = 10, .value = volume, .show_value = true, .on_change = ctx.on(Rec, &rec, Rec.changed) }).mount(scope, ctx);
    defer ctx.freeNode(result.wrapper);
    const rt = runtimeOf(result);
    try std.testing.expectEqualStrings("20.0", rt.value_text_node.?.getText().?.content);

    volume.set(60); // External drive: view, text, a11y all follow, no on_change trigger
    try std.testing.expectEqual(@as(f32, 60), rt.shown);
    try std.testing.expectEqualStrings("60.0", rt.value_text_node.?.getText().?.content);
    try std.testing.expectEqual(@as(f32, 60), result.wrapper.behavior.interaction.a11y.?.value_now);
    try std.testing.expectEqual(@as(u32, 0), rec.calls);

    ctx.owner.beginBatch(); // Real input all in host batch
    _ = sliderKeyHandler(.right, .{}, @ptrCast(rt));
    ctx.owner.endBatch();
    try std.testing.expectEqual(@as(f32, 70), volume.peek());
    try std.testing.expectEqual(@as(u32, 1), rec.calls);
    try std.testing.expectEqual(@as(f32, 70), rec.last);
    try std.testing.expectEqualStrings("70.0", rt.value_text_node.?.getText().?.content);
}

test "Slider: a split parent can transform the proposal; on_change gets what landed" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const Parent = struct {
        v: *Signal(f32),
        fn write(self: *@This(), proposed: f32) void {
            self.v.set(@min(proposed, 50)); // Cap 50
        }
    };
    var parent = Parent{ .v = try scope.createSignal(f32, 40) };
    var landed: f32 = 0;
    const result = try Slider(.{ .min = 0, .max = 100, .step = 10, .value = reactive.split(parent.v, ctx.on(Parent, &parent, Parent.write)), .on_change = ctx.on(f32, &landed, struct {
        fn f(out: *f32, v: f32) void {
            out.* = v;
        }
    }.f) }).mount(scope, ctx);
    defer ctx.freeNode(result.wrapper);
    try std.testing.expect(result.value == null);
    runtimeOf(result).propose(90, false);
    try std.testing.expectEqual(@as(f32, 50), parent.v.peek());
    try std.testing.expectEqual(@as(f32, 50), landed);
    try std.testing.expectEqual(@as(f32, 50), runtimeOf(result).shown);
}

test "Slider: dynamic disabled blocks input and updates focus / a11y / colors" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const off = try scope.createSignal(bool, false);
    const result = try Slider(.{ .value = 30, .disabled = off }).mount(scope, ctx);
    defer ctx.freeNode(result.wrapper);
    const rt = runtimeOf(result);
    try std.testing.expect(result.wrapper.behavior.interaction.focusable);
    try std.testing.expect(Color.eql(rt.fill_node.getBackground(), ctx.tokens.tokens.color.accent));

    off.set(true);
    try std.testing.expect(!result.wrapper.behavior.interaction.focusable);
    try std.testing.expect(result.wrapper.behavior.interaction.a11y.?.disabled);
    try std.testing.expect(Color.eql(rt.fill_node.getBackground(), ctx.tokens.tokens.color.fg_disabled));
    try std.testing.expectEqual(EventResult.ignored, sliderKeyHandler(.right, .{}, @ptrCast(rt)));
    try std.testing.expect(!setA11ySliderValue(rt, 80));
    try std.testing.expectEqual(@as(f32, 30), result.value.?.peek());

    // When disabled, hover highlight not shown
    rt.hovered.set(true);
    try std.testing.expect(Color.eql(thumbBorderTarget(rt), ctx.tokens.tokens.color.fg_disabled));

    off.set(false);
    try std.testing.expect(Color.eql(thumbBorderTarget(rt), ctx.tokens.tokens.color.accent_hover));
    try std.testing.expect(result.wrapper.behavior.interaction.focusable);
    _ = sliderKeyHandler(.right, .{}, @ptrCast(rt));
    try std.testing.expectEqual(@as(f32, 31), result.value.?.peek());
}

test "Slider: theme switch recolors track, fill, thumb and value text" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setTheme(&core.theme.light);
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const off = try scope.createSignal(bool, false);
    const result = try Slider(.{ .value = 30, .disabled = off, .show_value = true }).mount(scope, ctx);
    defer ctx.freeNode(result.wrapper);
    const rt = runtimeOf(result);

    ctx.setTheme(&core.theme.dark);
    const dark = &core.theme.dark;
    try std.testing.expect(rt.tokens == dark);
    try std.testing.expect(Color.eql(rt.track_node.getBackground(), dark.tokens.color.bg_tertiary));
    try std.testing.expect(Color.eql(rt.fill_node.getBackground(), dark.tokens.color.accent));
    try std.testing.expect(Color.eql(rt.thumb_node.getBackground(), styles.thumbBackground(.default, false, dark.tokens.color.range_fill, dark)));
    try std.testing.expect(Color.eql(thumbBorderTarget(rt), dark.tokens.color.accent));
    try std.testing.expect(Color.eql(rt.value_text_node.?.getText().?.color, dark.tokens.color.fg_secondary));

    off.set(true);
    try std.testing.expect(Color.eql(rt.fill_node.getBackground(), dark.tokens.color.fg_disabled));
}

test "Slider: a drag keeps the thumb highlighted after the pointer leaves the track" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const root = try core.box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 100 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const result = try Slider(.{ .value = 30 }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.wrapper);
    ctx.layout();
    const rt = runtimeOf(result);
    const r = rt.track_area_node.globalRect();
    _ = sliderEventHandler(.{ .mouse_down = .{ .x = r.x + r.w / 2, .y = r.y + r.h / 2 } }, @ptrCast(rt));
    try std.testing.expect(rt.dragging);
    rt.hovered.set(false);
    try std.testing.expect(Color.eql(thumbBorderTarget(rt), ctx.tokens.tokens.color.accent_hover));
    _ = sliderEventHandler(.{ .mouse_up = .{ .x = r.x, .y = r.y } }, @ptrCast(rt));
    try std.testing.expect(!rt.dragging);
    try std.testing.expect(Color.eql(thumbBorderTarget(rt), ctx.tokens.tokens.color.accent));
}

fn thumbBorderTarget(rt: *SliderRuntime) Color {
    const slot = rt.thumb_node.frame_state.frame_local.runtime.transitions.?.find(.border_color).?;
    return if (slot.active) slot.to_color else rt.thumb_node.style.border.color;
}

test "Slider: arrow keys move a continuous slider by 1% of the range" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const result = try Slider(.{ .min = 0, .max = 10, .step = 0, .value = 5 }).mount(scope, ctx);
    defer ctx.freeNode(result.wrapper);
    _ = sliderKeyHandler(.right, .{}, @ptrCast(runtimeOf(result)));
    try std.testing.expectApproxEqAbs(@as(f32, 5.1), result.value.?.peek(), 0.0001);
    _ = sliderKeyHandler(.left, .{}, @ptrCast(runtimeOf(result)));
    _ = sliderKeyHandler(.left, .{}, @ptrCast(runtimeOf(result)));
    try std.testing.expectApproxEqAbs(@as(f32, 4.9), result.value.?.peek(), 0.0001);
}

test "Slider: disabling mid-drag ends the drag" {
    const cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(400, 100);
    const root = try box(cx, .{ .width = .{ .px = 400 }, .height = .{ .px = 100 } }, .{});
    cx.root = root;
    const scope = try Scope.init(cx.allocator, null, cx.owner);
    defer scope.dispose();
    const off = try scope.createSignal(bool, false);
    const slider = try Slider(.{ .value = 0, .disabled = off }).mount(scope, cx);
    try root.appendChild(cx.allocator, slider.wrapper);
    cx.layout();
    const rt = runtimeOf(slider);
    const rect = rt.track_node.globalRect();
    _ = cx.dispatcher.dispatch(.{ .mouse_down = .{ .x = rect.x + rect.w * 0.2, .y = rect.y } }, rt.track_area_node);
    try std.testing.expect(rt.dragging);
    try std.testing.expectEqual(@as(f32, 20), slider.value.?.peek());
    off.set(true);
    try std.testing.expect(!rt.dragging);
    try std.testing.expect(cx.dispatcher.pointer_capture_handle == null);
    _ = cx.dispatcher.dispatch(.{ .mouse_move = .{ .x = rect.x + rect.w * 0.9, .y = rect.y, .dx = 0, .dy = 0 } }, rt.track_area_node);
    try std.testing.expectEqual(@as(f32, 20), slider.value.?.peek());
}

test "slider: 动态 disabled / 受控值的 mount 在任意分配点失败时不泄漏（sweep）" {
    const sw = @import("../oom_sweep.zig");
    try sw.sweepMount("slider(dynamic)", struct {
        fn m(scope: *sw.Scope, cx: *sw.Cx) anyerror!?*sw.Node {
            const v = try scope.createSignal(f32, 40);
            const off = try scope.createSignal(bool, false);
            return (try Slider(.{ .value = v, .disabled = off, .show_value = true }).mount(scope, cx)).wrapper;
        }
    }.m);
}

// styles.zig test collection, this line required, see docs/STYLING.md
test {
    _ = @import("styles.zig");
}

// Per-alloc OOM sweep, see src/ui/components/oom_sweep.zig
test "slider: mount 在任意分配点失败时不泄漏（sweep）" {
    const sw = @import("../oom_sweep.zig");
    try sw.sweepMount("slider", struct {
        fn m(scope: *sw.Scope, cx: *sw.Cx) anyerror!?*sw.Node {
            return (try Slider(.{ .min = 0, .max = 100, .value = 50 }).mount(scope, cx)).wrapper;
        }
    }.m);
}

test "Slider: pointer step feedback is discrete and programmatic updates are silent" {
    const sdk_mod = @import("system_sdk");
    const Mock = struct {
        count: usize = 0,
        fail: bool = false,
        last_pattern: ?sdk_mod.HapticFeedbackPattern = null,
        fn deinit(_: *anyopaque, _: Allocator) void {}
        fn pump(_: *anyopaque, _: *sdk_mod.EventQueue, _: u32) sdk_mod.SdkError!sdk_mod.PumpResult {
            return .{};
        }
        fn perform(ptr: *anyopaque, pattern: sdk_mod.HapticFeedbackPattern) sdk_mod.SdkError!void {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            self.last_pattern = pattern;
            self.count += 1;
            if (self.fail) return error.BackendFailure;
        }
    };
    var backend = Mock{};
    const vt = sdk_mod.BackendVTable{
        .name = "slider-haptic-mock",
        .deinit = Mock.deinit,
        .pump_events = Mock.pump,
        .perform_haptic_feedback = Mock.perform,
    };
    var sdk = sdk_mod.SystemSdk.init(std.testing.allocator, &backend, &vt, .{ .haptic_feedback = true });
    defer sdk.deinit();
    const cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.system_sdk = &sdk;
    cx.setViewport(400, 100);
    const scope = try Scope.init(cx.allocator, null, cx.owner);
    defer scope.dispose();
    const feedback = try scope.createSignal(bool, false);
    const pattern = try scope.createSignal(HapticFeedbackPattern, .alignment);
    const slider = try Slider(.{ .min = 0, .max = 10, .step = 1, .value = 5, .haptic_feedback = feedback, .haptic_pattern = pattern }).mount(scope, cx);
    cx.root = slider.wrapper;
    cx.layout();
    const rt = runtimeOf(slider);
    const value = slider.value.?;
    const rect = rt.track_node.globalRect();
    const context: ?*anyopaque = @ptrCast(rt);
    // Default-off must hold even on a capable device and a changed step.
    rt.setFromScreenX(rect.x + rect.w * 0.7);
    try std.testing.expectEqual(@as(f32, 7), value.peek());
    try std.testing.expectEqual(@as(usize, 0), backend.count);
    value.set(5);
    // The application can change its user's preference without remounting.
    feedback.set(true);
    _ = sliderEventHandler(.{ .mouse_down = .{ .x = rect.x + rect.w * 0.5, .y = rect.y } }, context);
    try std.testing.expectEqual(@as(usize, 0), backend.count);
    _ = sliderEventHandler(.{ .mouse_move = .{ .x = rect.x + rect.w * 0.61, .y = rect.y } }, context);
    try std.testing.expectEqual(@as(f32, 6), value.peek());
    try std.testing.expectEqual(@as(usize, 1), backend.count);
    try std.testing.expectEqual(sdk_mod.HapticFeedbackPattern.alignment, backend.last_pattern.?);
    _ = sliderEventHandler(.{ .mouse_move = .{ .x = rect.x + rect.w * 0.64, .y = rect.y } }, context);
    try std.testing.expectEqual(@as(usize, 1), backend.count);
    // Crossing several steps in one sample requests just one pulse; clamping
    // beyond an already reached endpoint does not repeat it.
    rt.setFromScreenX(rect.x + rect.w * 2);
    rt.setFromScreenX(rect.x + rect.w * 3);
    try std.testing.expectEqual(@as(usize, 2), backend.count);
    _ = sliderEventHandler(.{ .mouse_up = .{ .x = rect.x + rect.w, .y = rect.y } }, context);
    _ = sliderEventHandler(.{ .mouse_move = .{ .x = rect.x, .y = rect.y } }, context);
    value.set(4);
    _ = sliderKeyHandler(.right, .{}, context);
    _ = setA11ySliderValue(rt, 3);
    try std.testing.expectEqual(@as(usize, 2), backend.count);
    rt.step = 0;
    rt.setFromScreenX(rect.x + rect.w * 0.52);
    try std.testing.expectEqual(@as(usize, 2), backend.count);
    rt.step = 1;
    backend.fail = true;
    rt.setFromScreenX(rect.x + rect.w * 0.7);
    try std.testing.expectEqual(@as(f32, 7), value.peek());
    try std.testing.expectEqual(@as(usize, 3), backend.count);
    sdk.capabilities.haptic_feedback = false;
    rt.setFromScreenX(rect.x + rect.w * 0.8);
    try std.testing.expectEqual(@as(f32, 8), value.peek());
    try std.testing.expectEqual(@as(usize, 3), backend.count);
    feedback.set(false);
    sdk.capabilities.haptic_feedback = true;
    rt.setFromScreenX(rect.x + rect.w * 0.9);
    try std.testing.expectEqual(@as(usize, 3), backend.count);
    // Selecting a pattern alone never enables feedback or emits a request.
    pattern.set(.generic);
    rt.setFromScreenX(rect.x + rect.w * 0.2);
    try std.testing.expectEqual(@as(usize, 3), backend.count);
    backend.fail = false;
    feedback.set(true);
    rt.setFromScreenX(rect.x + rect.w * 0.3);
    try std.testing.expectEqual(sdk_mod.HapticFeedbackPattern.generic, backend.last_pattern.?);
    pattern.set(.level_change);
    rt.setFromScreenX(rect.x + rect.w * 0.4);
    try std.testing.expectEqual(sdk_mod.HapticFeedbackPattern.level_change, backend.last_pattern.?);
    try std.testing.expectEqual(@as(usize, 5), backend.count);
}

test "Slider: mouse down tolerates destruction from change or previous capture owner" {
    for ([_]bool{ false, true }) |destroy_on_capture_loss| {
        const cx = try Cx.init(std.testing.allocator, std.testing.io);
        defer cx.deinit();
        cx.setViewport(400, 100);
        const root = try box(cx, .{ .width = .{ .px = 400 }, .height = .{ .px = 100 } }, .{});
        cx.root = root;
        const scope = try Scope.init(cx.allocator, null, cx.owner);
        defer scope.dispose();
        const slider = try Slider(.{ .value = 0 }).mount(scope, cx);
        try root.appendChild(cx.allocator, slider.wrapper);
        const old_owner = try box(cx, .{}, .{});
        try root.appendChild(cx.allocator, old_owner);
        const State = struct {
            cx: *Cx,
            wrapper: *Node,
            changes: usize = 0,
            removals: usize = 0,
            fn remove(self: *@This()) void {
                self.removals += 1;
                self.cx.detachChild(self.wrapper.parent.?, self.wrapper);
                self.cx.freeNode(self.wrapper);
            }
            fn change(self: *@This(), _: f32) void {
                self.changes += 1;
                self.remove();
            }
            fn lost(node: *Node) void {
                const self: *@This() = @ptrCast(@alignCast(node.behavior.events.event_context.?));
                self.remove();
            }
        };
        var state = State{ .cx = cx, .wrapper = slider.wrapper };
        runtimeOf(slider).on_change = cx.on(State, &state, State.change);
        old_owner.behavior.events.event_context = &state;
        if (destroy_on_capture_loss) old_owner.on_capture_lost = State.lost;
        cx.layout();
        const target = runtimeOf(slider).track_area_node;
        const identity = cx.node_registry.handleFor(target);
        const rect = runtimeOf(slider).track_node.globalRect();
        if (destroy_on_capture_loss) cx.setPointerCapture(old_owner);
        _ = cx.dispatcher.dispatch(.{ .mouse_down = .{ .x = rect.x + rect.w * 0.7, .y = rect.y } }, target);
        try std.testing.expectEqual(@as(usize, 1), state.removals);
        try std.testing.expectEqual(@as(usize, if (destroy_on_capture_loss) 0 else 1), state.changes);
        try std.testing.expect(cx.node_registry.resolve(identity, null) == null);
        try std.testing.expect(cx.dispatcher.pointer_capture_handle == null);
    }
}

test "Slider: losing or failing to acquire capture ends pointer updates" {
    for ([_]bool{ false, true }) |redirect_during_acquire| {
        const cx = try Cx.init(std.testing.allocator, std.testing.io);
        defer cx.deinit();
        cx.setViewport(400, 100);
        const root = try box(cx, .{ .width = .{ .px = 400 }, .height = .{ .px = 100 } }, .{});
        cx.root = root;
        const scope = try Scope.init(cx.allocator, null, cx.owner);
        defer scope.dispose();
        const slider = try Slider(.{ .value = 0 }).mount(scope, cx);
        try root.appendChild(cx.allocator, slider.wrapper);
        const old_owner = try box(cx, .{}, .{});
        const replacement = try box(cx, .{}, .{});
        try root.appendChild(cx.allocator, old_owner);
        try root.appendChild(cx.allocator, replacement);
        const State = struct {
            cx: *Cx,
            replacement: *Node,
            changes: usize = 0,
            fn change(self: *@This(), _: f32) void {
                self.changes += 1;
            }
            fn lost(node: *Node) void {
                const self: *@This() = @ptrCast(@alignCast(node.behavior.events.event_context.?));
                self.cx.setPointerCapture(self.replacement);
            }
        };
        var state = State{ .cx = cx, .replacement = replacement };
        runtimeOf(slider).on_change = cx.on(State, &state, State.change);
        old_owner.behavior.events.event_context = &state;
        old_owner.on_capture_lost = State.lost;
        cx.layout();
        const rect = runtimeOf(slider).track_node.globalRect();
        if (redirect_during_acquire) cx.setPointerCapture(old_owner);
        _ = cx.dispatcher.dispatch(.{ .mouse_down = .{ .x = rect.x + rect.w * 0.5, .y = rect.y } }, runtimeOf(slider).track_area_node);
        if (!redirect_during_acquire) cx.setPointerCapture(replacement);
        try std.testing.expect(!runtimeOf(slider).dragging);
        const value = slider.value.?.peek();
        const changes = state.changes;
        _ = cx.dispatcher.dispatch(.{ .mouse_move = .{ .x = rect.x + rect.w * 0.9, .y = rect.y, .dx = 0, .dy = 0 } }, runtimeOf(slider).track_area_node);
        _ = cx.dispatcher.dispatch(.{ .mouse_up = .{ .x = rect.x + rect.w * 0.9, .y = rect.y } }, runtimeOf(slider).track_area_node);
        try std.testing.expectEqual(value, slider.value.?.peek());
        try std.testing.expectEqual(changes, state.changes);
        try std.testing.expectEqual(@as(usize, if (redirect_during_acquire) 0 else 1), changes);
        try std.testing.expect(cx.node_registry.resolve(cx.dispatcher.pointer_capture_handle, null) == replacement);
    }
}

test "Slider: range_* role tokens default to the semantic colors, drive every state and refresh on theme switch" {
    inline for (.{ &core.theme.light, &core.theme.dark, &core.theme.high_contrast }) |t| {
        const c = t.tokens.color;
        try std.testing.expectEqual(c.bg_tertiary, c.range_track);
        try std.testing.expectEqual(c.accent, c.range_fill);
        try std.testing.expectEqual(c.accent_hover, c.range_hover);
        try std.testing.expectEqual(c.accent_hover, c.range_drag);
        try std.testing.expectEqual(c.bg_primary, c.range_thumb);
        try std.testing.expectEqual(c.fg_disabled, c.range_disabled);
        try std.testing.expectEqual(c.fg_disabled, c.range_disabled_thumb);
    }
    // ZeroWork-style runtime theme: a copy of light with only the roles changed, applied with
    // setTheme after mount.
    var custom = core.theme.light;
    const c = &custom.tokens.color;
    c.range_track = Color.hex(0x111111);
    c.range_fill = Color.hex(0x222222);
    c.range_hover = Color.hex(0x333333);
    c.range_drag = Color.hex(0x444444);
    c.range_thumb = Color.hex(0x555555);
    c.range_disabled = Color.hex(0x666666);
    c.range_disabled_thumb = Color.hex(0x777777);

    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setTheme(&core.theme.light);
    const root = try core.box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 100 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const off = try scope.createSignal(bool, false);
    const result = try Slider(.{ .value = 30, .disabled = off }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.wrapper);
    ctx.layout();
    const rt = runtimeOf(result);

    ctx.setTheme(&custom);
    try std.testing.expect(rt.tokens == &custom);
    try std.testing.expectEqual(Color.hex(0x111111), rt.track_node.getBackground());
    try std.testing.expectEqual(Color.hex(0x222222), rt.fill_node.getBackground());
    try std.testing.expectEqual(Color.hex(0x555555), rt.thumb_node.getBackground());
    try std.testing.expectEqual(Color.hex(0x222222), thumbBorderTarget(rt));
    rt.hovered.set(true);
    try std.testing.expectEqual(Color.hex(0x333333), thumbBorderTarget(rt));
    const r = rt.track_area_node.globalRect();
    _ = sliderEventHandler(.{ .mouse_down = .{ .x = r.x + r.w / 2, .y = r.y + r.h / 2 } }, @ptrCast(rt));
    try std.testing.expect(rt.dragging);
    try std.testing.expectEqual(Color.hex(0x444444), thumbBorderTarget(rt));
    _ = sliderEventHandler(.{ .mouse_up = .{ .x = r.x, .y = r.y } }, @ptrCast(rt));
    rt.hovered.set(false);
    off.set(true);
    try std.testing.expectEqual(Color.hex(0x666666), rt.fill_node.getBackground());
    try std.testing.expectEqual(Color.hex(0x666666), thumbBorderTarget(rt));
    try std.testing.expectEqual(Color.hex(0x777777), rt.thumb_node.getBackground());

    // Back to the default theme: the semantic defaults return.
    ctx.setTheme(&core.theme.light);
    try std.testing.expectEqual(core.theme.light.tokens.color.bg_tertiary, rt.track_node.getBackground());
    try std.testing.expectEqual(core.theme.light.tokens.color.fg_disabled, rt.fill_node.getBackground());
}

test "Slider: default props keep the tree (no mark nodes, thumb shown, default paint)" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const result = try Slider(.{ .value = 30 }).mount(scope, ctx);
    defer ctx.freeNode(result.wrapper);
    const rt = runtimeOf(result);
    try std.testing.expectEqual(@as(usize, 1), result.wrapper.children.items.len);
    const area = result.wrapper.children.items[0];
    try std.testing.expectEqual(@as(usize, 2), area.children.items.len);
    try std.testing.expect(area.children.items[0] == rt.track_node);
    try std.testing.expect(area.children.items[1] == rt.thumb_node);
    try std.testing.expectEqual(@as(usize, 1), rt.track_node.children.items.len);
    try std.testing.expect(rt.thumb_node.style.display != .none);
    try std.testing.expectEqual(@as(usize, 0), rt.mark_dots.items.len);
    const c = ctx.tokens.tokens.color;
    try std.testing.expectEqual(c.range_track, rt.track_node.getBackground());
    try std.testing.expectEqual(c.range_thumb, rt.thumb_node.getBackground());
    try std.testing.expectEqual(c.range_fill, rt.fill_node.getBackground());
}

test "Slider: marks draw dots and labels on the track and follow their source" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const root = try core.box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 100 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const two = [_]SliderMark{
        .{ .value = 0, .label = "Low", .test_id = "mark.0", .label_test_id = "mark.0.label" },
        .{ .value = 4, .label = "Max", .test_id = "mark.1", .label_test_id = "mark.1.label" },
    };
    const three = [_]SliderMark{ .{ .value = 0, .label = "a" }, .{ .value = 2, .label = "b" }, .{ .value = 4, .label = "c" } };
    const one = [_]SliderMark{.{ .value = 2 }};
    const marks = try scope.createSignal([]const SliderMark, &two);
    const result = try Slider(.{ .min = 0, .max = 4, .step = 0, .width = 308, .thumb_size = 12, .track_height = 3, .value = 1, .marks = marks }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.wrapper);
    ctx.layout();
    const rt = runtimeOf(result);
    const area = rt.track_area_node;

    // Dots sit before the thumb (it covers them), labels after it; none is hit-testable.
    try std.testing.expectEqual(@as(usize, 2), rt.mark_dots.items.len);
    try std.testing.expectEqual(@as(usize, 2), rt.mark_labels.items.len);
    try std.testing.expectEqual(@as(usize, 2 + 2 + 2), area.children.items.len);
    try std.testing.expect(area.children.items[0] == rt.track_node);
    try std.testing.expect(area.children.items[1] == rt.mark_dots.items[0]);
    try std.testing.expect(area.children.items[2] == rt.mark_dots.items[1]);
    try std.testing.expect(area.children.items[3] == rt.thumb_node);
    const track = rt.track_node.globalRect();
    const d0 = rt.mark_dots.items[0].globalRect();
    const d1 = rt.mark_dots.items[1].globalRect();
    try std.testing.expectApproxEqAbs(track.x - 2, d0.x, 0.1);
    try std.testing.expectApproxEqAbs(track.x + track.w - 2, d1.x, 0.1);
    try std.testing.expectApproxEqAbs(@as(f32, 4), d0.w, 0.1);
    try std.testing.expectApproxEqAbs(@as(f32, 4), d0.h, 0.1);
    try std.testing.expectApproxEqAbs(area.globalRect().y + 4, d0.y, 0.1);
    try std.testing.expectEqualStrings("mark.1", rt.mark_dots.items[1].meta.ownership.meta.test_id.?);
    try std.testing.expect(!rt.mark_dots.items[0].frame_state.state_bits.flags.hit_test_visible);
    for (rt.mark_labels.items, [_][]const u8{ "Low", "Max" }, [_]f32{ d0.x, d1.x }) |label, words, dot_x| {
        try std.testing.expectEqualStrings(words, label.getText().?.content);
        try std.testing.expect(!label.getText().?.selectable);
        try std.testing.expect(!label.frame_state.state_bits.flags.hit_test_visible);
        try std.testing.expectEqual(ctx.tokens.tokens.color.fg_tertiary, label.getText().?.color);
        const r = label.globalRect();
        try std.testing.expectApproxEqAbs(dot_x + 2, r.x + r.w / 2, 0.1);
        try std.testing.expectApproxEqAbs(@as(f32, 32), r.w, 0.1);
        try std.testing.expectApproxEqAbs(area.globalRect().y + 12, r.y, 0.1);
    }
    try std.testing.expectEqualStrings("mark.0.label", rt.mark_labels.items[0].meta.ownership.meta.test_id.?);

    marks.set(&three);
    ctx.layout();
    try std.testing.expectEqual(@as(usize, 3), rt.mark_dots.items.len);
    try std.testing.expectEqual(@as(usize, 3), rt.mark_labels.items.len);
    try std.testing.expectEqual(@as(usize, 2 + 3 + 3), area.children.items.len);
    try std.testing.expectEqualStrings("b", rt.mark_labels.items[1].getText().?.content);
    try std.testing.expectApproxEqAbs(track.x + track.w / 2 - 2, rt.mark_dots.items[1].globalRect().x, 0.1);

    // A mark without a label draws only its dot.
    marks.set(&one);
    ctx.layout();
    try std.testing.expectEqual(@as(usize, 1), rt.mark_dots.items.len);
    try std.testing.expectEqual(@as(usize, 0), rt.mark_labels.items.len);
    try std.testing.expectEqual(@as(usize, 2 + 1), area.children.items.len);
    try std.testing.expect(area.children.items[2] == rt.thumb_node);
}

test "Slider: thumb_visible hides the thumb only" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const shown = try scope.createSignal(bool, false);
    const marks = [_]SliderMark{.{ .value = 50 }};
    const result = try Slider(.{ .value = 30, .thumb_visible = shown, .marks = @as([]const SliderMark, &marks) }).mount(scope, ctx);
    defer ctx.freeNode(result.wrapper);
    const rt = runtimeOf(result);
    try std.testing.expectEqual(core.Display.none, rt.thumb_node.style.display);
    try std.testing.expect(rt.track_node.style.display != .none);
    try std.testing.expect(rt.mark_dots.items[0].style.display != .none);
    shown.set(true);
    try std.testing.expect(rt.thumb_node.style.display != .none);
    shown.set(false);
    try std.testing.expectEqual(core.Display.none, rt.thumb_node.style.display);
}

test "Slider: stepped look paints a solid accent thumb and dots, fg-tertiary when disabled, and follows the theme" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setTheme(&core.theme.light);
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const off = try scope.createSignal(bool, false);
    const marks = [_]SliderMark{ .{ .value = 0 }, .{ .value = 100 } };
    const result = try Slider(.{ .value = 30, .disabled = off, .thumb_size = 12, .look = .stepped, .marks = @as([]const SliderMark, &marks) }).mount(scope, ctx);
    defer ctx.freeNode(result.wrapper);
    const rt = runtimeOf(result);
    const light = core.theme.light.tokens.color;
    try std.testing.expectEqual(light.accent, rt.thumb_node.getBackground());
    try std.testing.expectEqual(rt.fill_node.getBackground(), rt.thumb_node.getBackground());
    try std.testing.expectEqual(light.accent, rt.mark_dots.items[0].getBackground());
    try std.testing.expect(!Color.eql(rt.track_node.getBackground(), light.range_track));
    try std.testing.expectEqual(light.fg_tertiary.withAlpha(110), rt.track_node.getBackground());
    try std.testing.expectEqual(@as(f32, 0), rt.thumb_node.style.border.width);
    try std.testing.expectEqual(@as(f32, 6), rt.thumb_node.style.border.radius);

    off.set(true);
    try std.testing.expectEqual(light.fg_tertiary, rt.thumb_node.getBackground());
    try std.testing.expectEqual(light.fg_tertiary, rt.fill_node.getBackground());
    try std.testing.expectEqual(light.fg_tertiary, rt.mark_dots.items[1].getBackground());

    ctx.setTheme(&core.theme.dark);
    const dark = core.theme.dark.tokens.color;
    try std.testing.expectEqual(dark.fg_tertiary, rt.thumb_node.getBackground());
    try std.testing.expectEqual(dark.fg_tertiary.withAlpha(110), rt.track_node.getBackground());
    off.set(false);
    try std.testing.expectEqual(dark.accent, rt.thumb_node.getBackground());
    try std.testing.expectEqual(dark.accent, rt.mark_dots.items[0].getBackground());
}
