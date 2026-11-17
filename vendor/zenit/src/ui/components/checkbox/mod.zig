/// Checkbox, Radio, Switch Components
///
/// Signal-driven: hover state is managed via Signal, Effect auto-updates style. Toggle state is
/// kept in StateStore (involves DOM structure change).
///
/// Features:
/// - State management: toggle by StateStore, hover by Signal
/// - Event driven: on_event handles click
/// - Focus support: focusable, Tab navigation
/// - Label support
/// - Disabled state
/// - on_change callback
const std = @import("std");
const Allocator = std.mem.Allocator;
const core = @import("../../core.zig");
const ui_view = @import("../../view.zig");
const Cx = core.Cx;
const Node = core.Node;
const box = core.box;
const Color = core.Color;
const theme = core.theme;
const Signal = core.Signal;
const createEffect = core.createEffect;
const events = @import("../../events.zig");
const Event = events.Event;
const EventResult = events.EventResult;
const hooks = @import("../../hooks.zig");
const svg_assets = @import("../../svg_assets.zig");
const icons = @import("zenit_system_icons");
const reactive = @import("../../reactive.zig");
const Scope = reactive.Scope;
const Source = reactive.Source;
const Model = reactive.Model;
const Handler = core.Handler;
const bind_mod = @import("../../bind.zig");
const ui_split = reactive.split;
const eq_mod = @import("../../reactive/eq.zig");

const recipe_mod = @import("../../recipe.zig");

// Style layer factor to styles.yss; aliases below keep call-site and public API unchanged.
const styles = @import("_styles.yss.zig");
pub const CheckboxRecipe = styles.CheckboxRecipe;
pub const SwitchRecipe = styles.SwitchRecipe;
pub const CheckboxColors = styles.CheckboxColors;
const SwitchColors = styles.SwitchColors;
const controlRowStyle = styles.controlRowStyle;
const checkboxBoxStyle = styles.checkboxBoxStyle;
const checkIconStyle = styles.checkIconStyle;
const indetOverlayStyle = styles.indetOverlayStyle;
const controlLabelStyle = styles.controlLabelStyle;
const radioCircleStyle = styles.radioCircleStyle;
const radioDotStyle = styles.radioDotStyle;
const radioGroupContainerStyle = styles.radioGroupContainerStyle;
const switchTrackStyle = styles.switchTrackStyle;
const switchThumbStyle = styles.switchThumbStyle;
const switchLabelStyle = styles.switchLabelStyle;

// Checkbox
//
// Signal-first (docs/SIGNAL_API_DESIGN.md): `checked` is Model (local/bound/split);
// other changeable props are Source. View = f(checked, indeterminate, disabled), derived by one
// effect. Interaction only calls `Bound.propose`; if the parent refuses, the view stays unchanged.

/// Create Checkbox: `W.Checkbox(.{ .label = "Agree", .checked = agree })`.
/// props: checked (controlled value Model(bool))/indeterminate (read-only)/label/disabled/
/// on_change (only report settled value)/check_icon_asset.
/// View in checkbox.yix, style in styles.yss CheckboxParts.
pub const Checkbox = @import("_checkbox.yix.zig").Checkbox;

/// Click or spacebar
fn isToggleEvent(event: Event) bool {
    return switch (event) {
        .click => true,
        .key_down => |e| e.key == .space,
        else => false,
    };
}

// ==================== Radio / RadioGroup ====================

pub const RadioOption = struct {
    value: []const u8,
    label: []const u8,
    disabled: bool = false,
    /// Option node test_id (e2e / a11y locate; borrowed, outlive component)
    test_id: ?[]const u8 = null,
    /// A second line under the label (xs, fg-secondary, wraps; borrowed like `label`): the row
    /// aligns to the top with the circle on the label's first line, and the text is the option's
    /// accessibility description. null = the one-line row.
    description: ?[]const u8 = null,
};

/// Standalone Radio: display only (selection logic via RadioGroup). Props: checked / label /
/// disabled (all may signal).
pub const Radio = @import("_radio.yix.zig").Radio;

/// Radio group: W.RadioGroup(.{ .options = &opts, .value = choice }). Props: options / value
/// (controlled Model(?[]const u8), borrows option value string) / disabled / horizontal / on_change
/// (reports settled choice only). View in radio.yix, style in styles.yss RadioParts.
pub const RadioGroup = @import("_radio.yix.zig").RadioGroup;

// ==================== Switch ====================

/// Switch size: md (40x22, default) or sm (32x18) for dense rows and inline toolbars.
pub const SwitchSize = enum { sm, md };

/// Create Switch: W.Switch(.{ .label = "Wi-Fi", .checked = wifi }). Props: checked (controlled
/// Model(bool)) / label / size (sm / md) / disabled / on_change (reports settled value only).
/// View in switch.yix, style in styles.yss SwitchParts.
pub const Switch = @import("_switch.yix.zig").Switch;

/// Test fixture: Cx + root node + scope.
const Fixture = struct {
    cx: *Cx,
    root: *Node,
    scope: *Scope,

    fn init() !Fixture {
        const cx = try Cx.init(std.testing.allocator, std.testing.io);
        errdefer cx.deinit();
        const root = try box(cx, .{ .width = .{ .px = 200 }, .height = .{ .px = 100 } }, .{});
        cx.root = root;
        return .{ .cx = cx, .root = root, .scope = try Scope.init(std.testing.allocator, null, cx.owner) };
    }

    fn deinit(f: Fixture) void {
        f.scope.dispose();
        f.cx.deinit();
    }

    fn add(f: Fixture, node: *Node) !*Node {
        try f.root.appendChild(std.testing.allocator, node);
        return node;
    }

    fn effects(f: Fixture) usize {
        return f.cx.owner.graph.countByKind().get(.effect);
    }
};

/// Dispatch click / spacebar via real event handler (batch processing via Cx entry; here direct
/// handler call).
fn sendClick(node: *Node) EventResult {
    return node.behavior.events.on_event.?(.{ .click = .{ .x = 1, .y = 1, .button = .left, .click_count = 1 } }, node.behavior.events.event_context);
}

fn sendSpace(node: *Node) EventResult {
    return node.behavior.events.on_event.?(.{ .key_down = .{ .key = .space, .raw_keycode = 49, .modifiers = .{} } }, node.behavior.events.event_context);
}

/// Checkbox/Switch is view-declared button semantic node: click run on_click
fn press(node: *Node) void {
    const h = node.behavior.events.on_click.?;
    h.callback(h.context);
}

fn findText(n: *Node, text: []const u8) ?*Node {
    if (n.getText()) |t| if (std.mem.eql(u8, t.content, text)) return n;
    for (n.children.items) |c| if (findText(c, text)) |r| return r;
    return null;
}

fn checkmarkOf(cb: *Node) *Node {
    return cb.children.items[0].children.items[0];
}

fn indetOf(cb: *Node) *Node {
    return cb.children.items[0].children.items[1];
}

const BoolSink = struct {
    last: ?bool = null,
    calls: u32 = 0,
    fn changed(self: *BoolSink, v: bool) void {
        self.last = v;
        self.calls += 1;
    }
};

test "Checkbox: structure — label node only when a label is given" {
    const f = try Fixture.init();
    defer f.deinit();
    const with_label = try f.add(try Checkbox(.{ .label = "Remember me" }).mount(f.scope, f.cx));
    try std.testing.expectEqual(@as(usize, 2), with_label.children.items.len);
    try std.testing.expectEqualStrings("Remember me", with_label.behavior.interaction.a11y.?.label.?);
    const bare = try f.add(try Checkbox(.{}).mount(f.scope, f.cx));
    try std.testing.expectEqual(@as(usize, 1), bare.children.items.len);
    try std.testing.expectEqual(@as(usize, 2), bare.children.items[0].children.items.len); // checkmark + indet
}

test "Checkbox: local model — click toggles view, a11y and reports the landed value" {
    const f = try Fixture.init();
    defer f.deinit();
    var sink = BoolSink{};
    const cb = try f.add(try Checkbox(.{ .checked = true, .on_change = f.cx.on(BoolSink, &sink, BoolSink.changed) }).mount(f.scope, f.cx));
    try std.testing.expectEqual(@as(f32, 1), checkmarkOf(cb).getOpacity());
    press(cb);
    try std.testing.expectEqual(@as(f32, 0), checkmarkOf(cb).getOpacity());
    try std.testing.expect(!cb.behavior.interaction.a11y.?.checked.?);
    try std.testing.expectEqual(@as(?bool, false), sink.last);
    // Keyboard: Space via Cx synthesize click on focus node
    f.cx.setViewport(200, 100);
    f.cx.layout();
    f.cx.focus_manager.setFocus(cb);
    f.cx.handleKeyDown(.space, .{});
    try std.testing.expectEqual(@as(?bool, true), sink.last);
    try std.testing.expectEqual(@as(u32, 2), sink.calls);
}

test "Checkbox: bound model — external set drives the view, clicks write the signal" {
    const f = try Fixture.init();
    defer f.deinit();
    const agree = try f.scope.createSignal(bool, false);
    const cb = try f.add(try Checkbox(.{ .label = "Agree", .checked = agree }).mount(f.scope, f.cx));
    try std.testing.expectEqual(@as(f32, 0), checkmarkOf(cb).getOpacity());
    agree.set(true); // external drive
    try std.testing.expectEqual(@as(f32, 1), checkmarkOf(cb).getOpacity());
    try std.testing.expect(cb.behavior.interaction.a11y.?.checked.?);
    press(cb); // interaction write-back
    try std.testing.expect(!agree.peek());
    try std.testing.expectEqual(@as(f32, 0), checkmarkOf(cb).getOpacity());
}

test "Checkbox: split model — a rejected proposal leaves value and view unchanged" {
    const f = try Fixture.init();
    defer f.deinit();
    const agree = try f.scope.createSignal(bool, false);
    const Gate = struct {
        agree: *Signal(bool),
        allow: bool = false,
        fn propose(self: *@This(), v: bool) void {
            if (self.allow) self.agree.set(v);
        }
    };
    var gate = Gate{ .agree = agree };
    var sink = BoolSink{};
    const cb = try f.add(try Checkbox(.{
        .checked = ui_split(agree, f.cx.on(Gate, &gate, Gate.propose)),
        .on_change = f.cx.on(BoolSink, &sink, BoolSink.changed),
    }).mount(f.scope, f.cx));
    press(cb);
    try std.testing.expect(!agree.peek());
    try std.testing.expectEqual(@as(f32, 0), checkmarkOf(cb).getOpacity());
    try std.testing.expectEqual(@as(u32, 0), sink.calls);
    gate.allow = true;
    press(cb);
    try std.testing.expect(agree.peek());
    try std.testing.expectEqual(@as(f32, 1), checkmarkOf(cb).getOpacity());
    try std.testing.expectEqual(@as(?bool, true), sink.last);
}

test "Checkbox: indeterminate and disabled follow their sources" {
    const f = try Fixture.init();
    defer f.deinit();
    const mixed = try f.scope.createSignal(bool, true);
    const busy = try f.scope.createSignal(bool, true);
    const cb = try f.add(try Checkbox(.{ .indeterminate = mixed, .disabled = busy }).mount(f.scope, f.cx));
    try std.testing.expectEqual(@as(f32, 1), indetOf(cb).getOpacity());
    try std.testing.expect(cb.behavior.interaction.a11y.?.indeterminate);
    try std.testing.expect(!cb.behavior.interaction.focusable);
    press(cb); // disabled: don't change value
    try std.testing.expect(!cb.behavior.interaction.a11y.?.checked.?);
    busy.set(false);
    try std.testing.expect(cb.behavior.interaction.focusable);
    press(cb); // checked -> true
    try std.testing.expect(cb.behavior.interaction.a11y.?.checked.?);
    try std.testing.expectEqual(@as(f32, 0), indetOf(cb).getOpacity()); // checked no show mixed
    mixed.set(false);
    try std.testing.expect(!cb.behavior.interaction.a11y.?.indeterminate);
}

test "Checkbox: dynamic label from an owned text signal" {
    const f = try Fixture.init();
    defer f.deinit();
    const name = try f.scope.createText("Notify me", .{});
    const cb = try f.add(try Checkbox(.{ .label = name }).mount(f.scope, f.cx));
    try std.testing.expect(findText(cb, "Notify me") != null);
    name.set("Notify me about every reply in this thread");
    try std.testing.expect(findText(cb, "Notify me about every reply in this thread") != null);
    try std.testing.expectEqualStrings("Notify me about every reply in this thread", cb.behavior.interaction.a11y.?.label.?);
}

test "Checkbox: static props add no effects (zero-cost static)" {
    const f = try Fixture.init();
    defer f.deinit();
    const e0 = f.effects();
    _ = try f.add(try Checkbox(.{}).mount(f.scope, f.cx));
    const bare = f.effects() - e0;
    const e1 = f.effects();
    _ = try f.add(try Checkbox(.{ .label = "x", .disabled = false, .indeterminate = false, .checked = true }).mount(f.scope, f.cx));
    try std.testing.expectEqual(bare, f.effects() - e1);
}

test "Checkbox: 方框颜色过渡（底色 / 边框色都插值）" {
    const f = try Fixture.init();
    defer f.deinit();
    const on = try f.scope.createSignal(bool, false);
    const cb = try f.add(try Checkbox(.{ .checked = on }).mount(f.scope, f.cx));
    const box_node = cb.children.items[0];
    try std.testing.expectEqual(f.cx.tokens.tokens.color.checkbox_border, box_node.style.border.color);
    on.set(true);
    const slots = box_node.frame_state.frame_local.runtime.transitions.?;
    try std.testing.expect(slots.find(.background).?.active);
    const border = slots.find(.border_color).?;
    try std.testing.expect(border.active);
    // start color is pre-change, not post-reset baseline
    try std.testing.expectEqual(f.cx.tokens.tokens.color.checkbox_border, border.from_color);
    try std.testing.expectEqual(f.cx.tokens.tokens.color.accent, border.to_color);
    try std.testing.expectEqualStrings("Checkbox", cb.meta.ownership.meta.component_name.?);
}

test "Radio: basic" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 200 }, .height = .{ .px = 100 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);

    defer scope.dispose();

    const radio = try Radio(.{ .label = "Option 1" }).mount(scope, ctx);

    try root.appendChild(std.testing.allocator, radio);
    try std.testing.expectEqual(@as(usize, 2), radio.children.items.len);
}

test "Radio: checked render emits inner dot" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(120, 40);

    const root = try box(ctx, .{
        .width = .{ .px = 120 },
        .height = .{ .px = 40 },
        .background = ctx.tokens.tokens.color.bg_primary,
    }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const radio = try Radio(.{
        .checked = true,
        .label = "On",
    }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, radio);

    ctx.layout();
    _ = ctx.render();
    const commands = ctx.lowerForEncoderPaintTable();

    var saw_dot = false;
    for (commands) |cmd| if (cmd.isFillRect()) {
        const r = cmd;
        if (Color.eql(r.color.toColor(), ctx.tokens.tokens.color.button_primary_fg) and r.geom.w >= 7 and r.geom.h >= 7 and r.geom.w <= 10 and r.geom.h <= 10) {
            saw_dot = true;
        }
    };

    try std.testing.expect(saw_dot);
}

test "Radio: disabled checked uses LKxqO semantic colors without opacity" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{
        .width = .{ .px = 120 },
        .height = .{ .px = 40 },
    }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const radio = try Radio(.{
        .checked = true,
        .disabled = true,
        .label = "Disabled",
    }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, radio);

    // LKxqO: disabled background/dot, selected accent border; no blanket fading.
    try std.testing.expectApproxEqAbs(@as(f32, 1), radio.getOpacity(), 0.001);
    try std.testing.expectEqual(ctx.tokens.tokens.color.disabled_bg, radio.children.items[0].getBackground());
    try std.testing.expectEqual(ctx.tokens.tokens.color.fg_disabled, radio.children.items[0].children.items[0].getBackground());
    try std.testing.expectEqual(ctx.tokens.tokens.color.accent, radio.children.items[0].style.border.color);
}

test "RadioGroup: multiple options" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 200 }, .height = .{ .px = 200 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);

    defer scope.dispose();

    const options = [_]RadioOption{
        .{ .value = "a", .label = "Option A" },
        .{ .value = "b", .label = "Option B" },
        .{ .value = "c", .label = "Option C" },
    };

    const group = try RadioGroup(.{
        .options = &options,
        .value = "b",
    }).mount(scope, ctx);

    try root.appendChild(std.testing.allocator, group);
    try std.testing.expectEqual(@as(usize, 3), optionCount(group));
    // radio group always require one selected (UIA SelectionPattern.IsSelectionRequired)
    try std.testing.expectEqual(core.A11yRole.radiogroup, group.behavior.interaction.a11y.?.role);
    try std.testing.expect(group.behavior.interaction.a11y.?.required);
}

const StrSink = struct {
    last: [16]u8 = undefined,
    len: usize = 0,
    calls: u32 = 0,
    fn changed(self: *StrSink, v: []const u8) void {
        @memcpy(self.last[0..v.len], v);
        self.len = v.len;
        self.calls += 1;
    }
    fn value(self: *const StrSink) []const u8 {
        return self.last[0..self.len];
    }
};

fn radioDotOpacity(group: *Node, i: usize) f32 {
    return option(group, i).children.items[0].children.items[0].getOpacity();
}

/// RadioGroup i-th option (options from signal, keyed list area has anchor nodes before/after)
fn option(group: *Node, i: usize) *Node {
    var k: usize = 0;
    for (group.children.items) |c| {
        if (c.tag == .anchor) continue;
        if (k == i) return c;
        k += 1;
    }
    unreachable;
}

fn optionCount(group: *Node) usize {
    var k: usize = 0;
    for (group.children.items) |c| k += @intFromBool(c.tag != .anchor);
    return k;
}

test "RadioGroup: bound value — external set and clicks, disabled option ignored" {
    const f = try Fixture.init();
    defer f.deinit();
    const opts = [_]RadioOption{ .{ .value = "light", .label = "Light" }, .{ .value = "dark", .label = "Dark" }, .{ .value = "auto", .label = "Auto", .disabled = true } };
    const theme_sig = try f.scope.createSignal(?[]const u8, "light");
    var sink = StrSink{};
    const group = try f.add(try RadioGroup(.{ .options = &opts, .value = theme_sig, .on_change = f.cx.on(StrSink, &sink, StrSink.changed) }).mount(f.scope, f.cx));
    try std.testing.expect(option(group, 0).behavior.interaction.a11y.?.checked.?);
    theme_sig.set("dark"); // external drive
    try std.testing.expect(option(group, 1).behavior.interaction.a11y.?.checked.?);
    try std.testing.expect(!option(group, 0).behavior.interaction.a11y.?.checked.?);
    try std.testing.expectEqual(@as(u32, 0), sink.calls); // program write don't trigger on_change
    press(option(group, 0)); // interaction write-back
    try std.testing.expectEqualStrings("light", theme_sig.peek().?);
    try std.testing.expectEqualStrings("light", sink.value());
    press(option(group, 2)); // disabled item
    try std.testing.expectEqualStrings("light", theme_sig.peek().?);
    try std.testing.expectEqual(@as(u32, 1), sink.calls);
    press(option(group, 0)); // same value: no trigger
    try std.testing.expectEqual(@as(u32, 1), sink.calls);
}

test "RadioGroup: options from a signal rebuild the items" {
    const f = try Fixture.init();
    defer f.deinit();
    const two = [_]RadioOption{ .{ .value = "a", .label = "A" }, .{ .value = "b", .label = "B" } };
    const three = [_]RadioOption{ .{ .value = "a", .label = "A" }, .{ .value = "b", .label = "B" }, .{ .value = "c", .label = "C" } };
    const options = try f.scope.createSignal([]const RadioOption, &two);
    const group = try f.add(try RadioGroup(.{ .options = options, .value = "b" }).mount(f.scope, f.cx));
    try std.testing.expectEqual(@as(usize, 2), optionCount(group));
    options.set(&three);
    try std.testing.expectEqual(@as(usize, 3), optionCount(group));
    try std.testing.expect(option(group, 1).behavior.interaction.a11y.?.checked.?); // selected keep
    press(option(group, 2)); // new option interactive
    try std.testing.expect(option(group, 2).behavior.interaction.a11y.?.checked.?);
    try std.testing.expect(!option(group, 1).behavior.interaction.a11y.?.checked.?);
}

test "Radio: standalone radio follows its sources" {
    const f = try Fixture.init();
    defer f.deinit();
    const on = try f.scope.createSignal(bool, false);
    const r = try f.add(try Radio(.{ .label = "Solo", .checked = on }).mount(f.scope, f.cx));
    try std.testing.expect(!r.behavior.interaction.a11y.?.checked.?);
    on.set(true);
    try std.testing.expect(r.behavior.interaction.a11y.?.checked.?);
}

test "Switch: structure and checked render emits track and thumb" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(140, 40);
    const root = try box(ctx, .{ .width = .{ .px = 140 }, .height = .{ .px = 40 }, .background = ctx.tokens.tokens.color.bg_primary }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const sw = try Switch(.{ .checked = true, .label = "Enabled" }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, sw);
    try std.testing.expectEqual(@as(usize, 2), sw.children.items.len);

    ctx.layout();
    _ = ctx.render();
    const commands = ctx.lowerForEncoderPaintTable();
    var saw_track = false;
    var saw_thumb = false;
    for (commands) |cmd| if (cmd.isFillRect()) {
        const r = cmd;
        if (Color.eql(r.color.toColor(), ctx.tokens.tokens.color.accent) and r.geom.w >= 38 and r.geom.h >= 20) saw_track = true;
        if (Color.eql(r.color.toColor(), ctx.tokens.tokens.color.fg_inverse) and r.geom.w >= 16 and r.geom.h >= 16 and r.geom.w <= 20 and r.geom.h <= 20) saw_thumb = true;
    };
    try std.testing.expect(saw_track);
    try std.testing.expect(saw_thumb);
}

/// Switch is view-declared button semantic node: click run on_click, Space/Enter via Cx
/// synthesize click on focus node
fn clickSwitch(sw: *Node) void {
    const h = sw.behavior.events.on_click.?;
    h.callback(h.context);
}

test "Switch: sm size takes its track, thumb and travel from the sm size tokens" {
    const f = try Fixture.init();
    defer f.deinit();
    const on = try f.scope.createSignal(bool, true);
    const sw = try f.add(try Switch(.{ .checked = on, .size = .sm }).mount(f.scope, f.cx));
    const size = f.cx.tokens.tokens.size;
    const track = sw.children.items[0];
    const thumb = track.children.items[0];
    try std.testing.expectEqual(size.switch_width_sm, track.style.width.px);
    try std.testing.expectEqual(size.switch_height_sm, track.style.height.px);
    try std.testing.expectEqual(size.switch_thumb_sm, thumb.style.width.px);
    try std.testing.expectEqual(size.switch_thumb_sm, thumb.style.height.px);
    // On: the thumb rests 2px from the track's right edge, as at md.
    try std.testing.expectEqual(size.switch_width_sm - size.switch_thumb_sm - 2, thumb.style.translate_x);
    // md stays the default and keeps its own tokens.
    const md = try f.add(try Switch(.{ .checked = true }).mount(f.scope, f.cx));
    try std.testing.expectEqual(size.switch_width, md.children.items[0].style.width.px);
    try std.testing.expectEqual(size.switch_width - size.switch_thumb - 2, md.children.items[0].children.items[0].style.translate_x);
}

test "Switch: a theme that resizes the switch sets the thumb travel with switch-travel(-sm)" {
    const f = try Fixture.init();
    defer f.deinit();
    // A compact sm switch (26x14 track, 10 thumb): the on thumb rests 2px from the right edge,
    // 26 - 10 - 2 = 14, not the default sm travel of 16.
    var custom = theme.light;
    custom.tokens.size.switch_width_sm = 26;
    custom.tokens.size.switch_height_sm = 14;
    custom.tokens.size.switch_thumb_sm = 10;
    custom.tokens.size.switch_travel_sm = 14;
    custom.tokens.size.switch_travel = 18;
    f.cx.tokens = &custom;
    const sm = try f.add(try Switch(.{ .checked = true, .size = .sm }).mount(f.scope, f.cx));
    try std.testing.expectEqual(@as(f32, 14), sm.children.items[0].children.items[0].style.translate_x);
    const md = try f.add(try Switch(.{ .checked = true }).mount(f.scope, f.cx));
    try std.testing.expectEqual(@as(f32, 18), md.children.items[0].children.items[0].style.translate_x);
    // Off stays at the 2px inset.
    const off = try f.add(try Switch(.{ .checked = false, .size = .sm }).mount(f.scope, f.cx));
    try std.testing.expectEqual(@as(f32, 2), off.children.items[0].children.items[0].style.translate_x);
}

test "Switch: local model toggles and reports; disabled source blocks input" {
    const f = try Fixture.init();
    defer f.deinit();
    var sink = BoolSink{};
    const off = try f.scope.createSignal(bool, false);
    const sw = try f.add(try Switch(.{ .disabled = off, .on_change = f.cx.on(BoolSink, &sink, BoolSink.changed) }).mount(f.scope, f.cx));
    clickSwitch(sw);
    try std.testing.expectEqual(@as(?bool, true), sink.last);
    try std.testing.expect(sw.behavior.interaction.a11y.?.checked.?);
    // Keyboard: Space via Cx synthesize click on focus node
    f.cx.setViewport(200, 100);
    f.cx.layout();
    f.cx.focus_manager.setFocus(sw);
    f.cx.handleKeyDown(.space, .{});
    try std.testing.expectEqual(@as(?bool, false), sink.last);
    off.set(true);
    clickSwitch(sw);
    try std.testing.expectEqual(@as(u32, 2), sink.calls);
    // disabled exit Tab order, a11y sync
    try std.testing.expect(!sw.behavior.interaction.focusable);
    try std.testing.expect(sw.behavior.interaction.a11y.?.disabled);
}

test "Switch: bound model — external set moves the thumb with a transition" {
    const f = try Fixture.init();
    defer f.deinit();
    const wifi = try f.scope.createSignal(bool, false);
    const sw = try f.add(try Switch(.{ .label = "Wi-Fi", .checked = wifi }).mount(f.scope, f.cx));
    const thumb = sw.children.items[0].children.items[0];
    try std.testing.expectEqual(@as(f32, 2), thumb.style.translate_x);
    wifi.set(true);
    try std.testing.expect(sw.behavior.interaction.a11y.?.checked.?);
    // offset advance by transition declare in style (translate-x 200ms), target 20
    const slot = thumb.frame_state.frame_local.runtime.transitions.?.find(.translate_x).?;
    try std.testing.expect(slot.active);
    // LKxqO: off/on labels both use fg_primary; only the thumb moves.
    const label = sw.children.items[1];
    try std.testing.expectEqual(f.cx.tokens.tokens.color.fg_primary, label.getText().?.color);
    clickSwitch(sw);
    try std.testing.expect(!wifi.peek());
}

test "Switch: a click after an idle stretch without frames animates the thumb from the click" {
    // The host stops rendering while the window is idle, so the frame clock stays at the last
    // active frame while wall time runs on. A pointer click must still start the thumb's
    // translate transition at the click: the first frame after it shows the thumb in flight.
    const render_engine = @import("../../core/render_engine/mod.zig");
    const saved = render_engine.saveFrameClock();
    defer render_engine.restoreFrameClock(saved);
    const f = try Fixture.init();
    defer f.deinit();
    const on = try f.scope.createSignal(bool, false);
    const sw = try f.add(try Switch(.{ .checked = on }).mount(f.scope, f.cx));
    f.cx.setViewport(200, 100);
    for (0..2) |_| {
        f.cx.requestRedraw();
        f.cx.advanceFrameClock();
        f.cx.layout();
        _ = f.cx.render();
    }
    f.cx.advanceFrameClock(); // idle frame: the clock freezes
    f.cx.layout();
    _ = f.cx.render();
    // One second passes with no frame at all (the host's frame loop is stopped).
    f.cx.clock_epoch.?.timestamp -= std.time.ns_per_s;
    f.cx.last_frame_instant.?.timestamp -= std.time.ns_per_s;
    const r = sw.globalRect();
    f.cx.handleMouseDown(r.x + r.w / 2, r.y + r.h / 2, .{});
    f.cx.handleMouseUp(r.x + r.w / 2, r.y + r.h / 2);
    // Pointer motion before the next frame (the harness updates its automation cursor after
    // every click) refreshes the hit scene at the frozen frame clock.
    f.cx.handleMouseMove(r.x + r.w / 2 + 1, r.y + r.h / 2);
    try std.testing.expect(on.peek());
    f.cx.advanceFrameClock();
    f.cx.layout();
    _ = f.cx.render();
    const thumb = sw.children.items[0].children.items[0];
    const slot = thumb.frame_state.frame_local.runtime.transitions.?.find(.translate_x).?;
    try std.testing.expect(slot.active);
    try std.testing.expect(thumb.style.translate_x < 19);
}

test "Switch: split model — rejected toggle keeps the signal" {
    const f = try Fixture.init();
    defer f.deinit();
    const on = try f.scope.createSignal(bool, true);
    const Deny = struct {
        fn propose(_: *@This(), _: bool) void {}
    };
    var deny = Deny{};
    const sw = try f.add(try Switch(.{ .checked = ui_split(on, f.cx.on(Deny, &deny, Deny.propose)) }).mount(f.scope, f.cx));
    clickSwitch(sw);
    try std.testing.expect(on.peek());
    try std.testing.expect(sw.behavior.interaction.a11y.?.checked.?);
}

test "Switch: 静态 props 不建 memo；焦点环已挂上" {
    const f = try Fixture.init();
    defer f.deinit();
    const before = f.cx.owner.graph.countByKind().get(.memo);
    const sw = try f.add(try Switch(.{ .label = "Static", .checked = true }).mount(f.scope, f.cx));
    try std.testing.expectEqual(before, f.cx.owner.graph.countByKind().get(.memo));
    try std.testing.expect(sw.meta.per_frame.hooks.slots.focus_ring_anim != null);
    try std.testing.expectEqualStrings("Switch", sw.meta.ownership.meta.component_name.?);
}

test {
    _ = @import("_styles.yss.zig");
}

// per-alloc OOM sweep, see src/ui/components/oom_sweep.zig
test "checkbox(indeterminate): mount 在任意分配点失败时不泄漏（sweep）" {
    try @import("../oom_sweep.zig").sweepMount("checkbox(indeterminate)", struct {
        fn m(scope: *Scope, cx: *Cx) anyerror!?*Node {
            return try Checkbox(.{ .label = "check", .indeterminate = true }).mount(scope, cx);
        }
    }.m);
}

// per-alloc OOM sweep, see src/ui/components/oom_sweep.zig
test "radio_group: mount 在任意分配点失败时不泄漏（sweep）" {
    try @import("../oom_sweep.zig").sweepMount("radio_group", struct {
        fn m(scope: *Scope, cx: *Cx) anyerror!?*Node {
            const opts = [_]RadioOption{ .{ .value = "a", .label = "A" }, .{ .value = "b", .label = "B", .disabled = true } };
            return try RadioGroup(.{ .options = &opts, .value = "a" }).mount(scope, cx);
        }
    }.m);
}

// per-alloc OOM sweep, see src/ui/components/oom_sweep.zig
test "switch: mount 在任意分配点失败时不泄漏（sweep）" {
    try @import("../oom_sweep.zig").sweepMount("switch", struct {
        fn m(scope: *Scope, cx: *Cx) anyerror!?*Node {
            return try Switch(.{ .label = "toggle", .checked = true }).mount(scope, cx);
        }
    }.m);
}

test "radio_group(options signal): mount 在任意分配点失败时不泄漏（sweep）" {
    try @import("../oom_sweep.zig").sweepMount("radio_group(signal)", struct {
        const opts = [_]RadioOption{ .{ .value = "a", .label = "A" }, .{ .value = "b", .label = "B" } };
        fn m(scope: *Scope, cx: *Cx) anyerror!?*Node {
            const o = try scope.createSignal([]const RadioOption, &opts);
            const v = try scope.createSignal(?[]const u8, "a");
            return try RadioGroup(.{ .options = o, .value = v }).mount(scope, cx);
        }
    }.m);
}

test "RadioGroup: static options are copied, so a caller's stack array may go away" {
    const f = try Fixture.init();
    defer f.deinit();
    var sink = StrSink{};
    const group = blk: {
        var opts = [_]RadioOption{ .{ .value = "a", .label = "A" }, .{ .value = "b", .label = "B" } };
        const g = try RadioGroup(.{ .options = &opts, .on_change = f.cx.on(StrSink, &sink, StrSink.changed) }).mount(f.scope, f.cx);
        opts[1] = .{ .value = "clobbered", .label = "X" }; // caller later clobber/free own array
        break :blk g;
    };
    _ = try f.add(group);
    press(option(group, 1));
    try std.testing.expectEqualStrings("b", sink.value());
}

test "RadioGroup: mount builds the selected state directly (no transition at mount)" {
    const f = try Fixture.init();
    defer f.deinit();
    const opts = [_]RadioOption{ .{ .value = "x", .label = "X" }, .{ .value = "y", .label = "Y" } };
    const group = try f.add(try RadioGroup(.{ .options = &opts, .value = "y" }).mount(f.scope, f.cx));
    for (group.children.items) |radio| {
        const circle = radio.children.items[0];
        const dot = circle.children.items[0];
        for ([_]*Node{ circle, dot }) |n| {
            if (n.frame_state.frame_local.runtime.transitions) |slots| try std.testing.expect(!slots.any_active);
        }
    }
    try std.testing.expectEqual(@as(f32, 1), radioDotOpacity(group, 1));
}

test "RadioGroup: an equal-content options array does not rebuild the items" {
    const f = try Fixture.init();
    defer f.deinit();
    // string literal deduplicate (same addr), need 'same content, diff addr' must use separate
    // buffer
    const Arrays = struct {
        var va1 = "a".*;
        var la1 = "A".*;
        var vb1 = "b".*;
        var lb1 = "B".*;
        var va2 = "a".*;
        var la2 = "A".*;
        var vb2 = "b".*;
        var lb2 = "B".*;
        var a: [2]RadioOption = undefined;
        var b: [2]RadioOption = undefined;
    };
    Arrays.a = .{ .{ .value = &Arrays.va1, .label = &Arrays.la1 }, .{ .value = &Arrays.vb1, .label = &Arrays.lb1 } };
    Arrays.b = .{ .{ .value = &Arrays.va2, .label = &Arrays.la2 }, .{ .value = &Arrays.vb2, .label = &Arrays.lb2 } };
    // memo switch between two same-content diff-addr arrays: memo compare key byte-wise, propagate
    // down
    const which = try f.scope.createSignal(bool, false);
    const options = try f.scope.createMemo([]const RadioOption, .{ .which = which }, struct {
        fn pick(c: anytype) []const RadioOption {
            return if (c.which.get()) Arrays.b[0..] else Arrays.a[0..];
        }
    }.pick);
    const group = try f.add(try RadioGroup(.{ .options = options }).mount(f.scope, f.cx));
    const first = group.children.items[0];
    which.set(true);
    // confirm view truly re-ran (memo byte compare, diff addr means propagate), just no rebuild
    try std.testing.expect(options.peek().ptr == &Arrays.b);
    try std.testing.expect(group.children.items[0] == first);
}

test "Checkbox / Radio: role tokens default to the semantic colors and recolor the indicator" {
    // Defaults alias the semantic colors the recipe read before the roles existed.
    inline for (.{ &theme.light, &theme.dark, &theme.high_contrast }) |t| {
        const c = t.tokens.color;
        try std.testing.expectEqual(c.accent, c.checkbox_checked_bg);
        try std.testing.expectEqual(c.fg_inverse, c.checkbox_fg);
        try std.testing.expectEqual(c.fg_disabled, c.checkbox_disabled_fg);
        try std.testing.expectEqual(c.disabled_bg, c.checkbox_disabled_checked_bg);
    }
    const f = try Fixture.init();
    defer f.deinit();
    var custom = theme.light;
    const c = &custom.tokens.color;
    c.checkbox_bg = Color.hex(0x010101);
    c.checkbox_border = Color.hex(0x020202);
    c.checkbox_checked_bg = Color.hex(0x030303);
    c.checkbox_fg = Color.hex(0x040404);
    c.checkbox_disabled_bg = Color.hex(0x050505);
    c.checkbox_disabled_border = Color.hex(0x060606);
    c.checkbox_disabled_checked_bg = Color.hex(0x070707);
    c.checkbox_disabled_fg = Color.hex(0x080808);
    f.cx.setTheme(&custom);
    const off = try f.add(try Checkbox(.{}).mount(f.scope, f.cx));
    try std.testing.expectEqual(Color.hex(0x010101), off.children.items[0].getBackground());
    try std.testing.expectEqual(Color.hex(0x020202), off.children.items[0].style.border.color);
    const on = try f.add(try Checkbox(.{ .checked = true }).mount(f.scope, f.cx));
    try std.testing.expectEqual(Color.hex(0x030303), on.children.items[0].getBackground());
    try std.testing.expectEqual(Color.hex(0x030303), on.children.items[0].style.border.color);
    try std.testing.expectEqual(Color.hex(0x040404), checkmarkOf(on).tintMode().?.color);
    const dis_off = try f.add(try Checkbox(.{ .disabled = true }).mount(f.scope, f.cx));
    try std.testing.expectEqual(Color.hex(0x050505), dis_off.children.items[0].getBackground());
    try std.testing.expectEqual(Color.hex(0x060606), dis_off.children.items[0].style.border.color);
    const dis_on = try f.add(try Checkbox(.{ .checked = true, .disabled = true }).mount(f.scope, f.cx));
    try std.testing.expectEqual(Color.hex(0x070707), dis_on.children.items[0].getBackground());
    try std.testing.expectEqual(Color.hex(0x080808), checkmarkOf(dis_on).tintMode().?.color);
    // Radio shares the checkbox roles.
    const radio_on = try f.add(try Radio(.{ .checked = true }).mount(f.scope, f.cx));
    try std.testing.expectEqual(Color.hex(0x030303), radio_on.children.items[0].getBackground());
    try std.testing.expectEqual(Color.hex(0x040404), radio_on.children.items[0].children.items[0].getBackground());
    const radio_off = try f.add(try Radio(.{}).mount(f.scope, f.cx));
    try std.testing.expectEqual(Color.hex(0x010101), radio_off.children.items[0].getBackground());
    try std.testing.expectEqual(Color.hex(0x020202), radio_off.children.items[0].style.border.color);
    const radio_dis = try f.add(try Radio(.{ .checked = true, .disabled = true }).mount(f.scope, f.cx));
    try std.testing.expectEqual(Color.hex(0x070707), radio_dis.children.items[0].getBackground());
    try std.testing.expectEqual(Color.hex(0x080808), radio_dis.children.items[0].children.items[0].getBackground());
    const radio_dis_off = try f.add(try Radio(.{ .disabled = true }).mount(f.scope, f.cx));
    try std.testing.expectEqual(Color.hex(0x050505), radio_dis_off.children.items[0].getBackground());
}

test "Switch: role tokens default to the semantic colors and recolor track and thumb per state" {
    inline for (.{ &theme.light, &theme.dark, &theme.high_contrast }) |t| {
        const c = t.tokens.color;
        try std.testing.expectEqual(c.accent, c.switch_track_on);
        try std.testing.expectEqual(c.fg_inverse, c.switch_thumb_on);
        try std.testing.expectEqual(c.border, c.switch_disabled_track_on);
        try std.testing.expectEqual(c.border, c.switch_disabled_track_off);
        try std.testing.expectEqual(c.bg_secondary, c.switch_disabled_thumb_on);
        try std.testing.expectEqual(c.bg_secondary, c.switch_disabled_thumb_off);
    }
    const f = try Fixture.init();
    defer f.deinit();
    var custom = theme.light;
    const c = &custom.tokens.color;
    c.switch_track_on = Color.hex(0x111111);
    c.switch_thumb_on = Color.hex(0x121212);
    c.switch_track_off = Color.hex(0x131313);
    c.switch_thumb = Color.hex(0x141414);
    c.switch_disabled_track_on = Color.hex(0x151515);
    c.switch_disabled_thumb_on = Color.hex(0x161616);
    c.switch_disabled_track_off = Color.hex(0x171717);
    c.switch_disabled_thumb_off = Color.hex(0x181818);
    f.cx.setTheme(&custom);
    const Case = struct { checked: bool, disabled: bool, track: u24, thumb: u24 };
    for ([_]Case{
        .{ .checked = true, .disabled = false, .track = 0x111111, .thumb = 0x121212 },
        .{ .checked = false, .disabled = false, .track = 0x131313, .thumb = 0x141414 },
        .{ .checked = true, .disabled = true, .track = 0x151515, .thumb = 0x161616 },
        .{ .checked = false, .disabled = true, .track = 0x171717, .thumb = 0x181818 },
    }) |case| {
        const sw = try f.add(try Switch(.{ .checked = case.checked, .disabled = case.disabled }).mount(f.scope, f.cx));
        const track = sw.children.items[0];
        try std.testing.expectEqual(Color.hex(case.track), track.getBackground());
        try std.testing.expectEqual(Color.hex(case.thumb), track.children.items[0].getBackground());
    }
}

test "Checkbox: size / label_font_size override the box, scale the glyphs and keep defaults at null" {
    const f = try Fixture.init();
    defer f.deinit();
    const t = f.cx.tokens.tokens;
    const def = try f.add(try Checkbox(.{ .label = "a", .indeterminate = true }).mount(f.scope, f.cx));
    try std.testing.expectEqual(t.size.checkbox, def.children.items[0].style.width.px);
    try std.testing.expectEqual(t.size.checkbox, def.children.items[0].style.height.px);
    try std.testing.expectEqual(@as(f32, 12), checkmarkOf(def).style.width.px);
    try std.testing.expectEqual(t.size.checkbox, indetOf(def).style.width.px);
    try std.testing.expectEqual(@as(f32, 12), indetOf(def).children.items[0].style.width.px);
    try std.testing.expectEqual(t.font_size.md, findText(def, "a").?.getText().?.font_size);
    for ([_][2]f32{ .{ 13, 10.5 }, .{ 14, 11 }, .{ 16, 11 } }) |sz| {
        const cb = try f.add(try Checkbox(.{ .label = "b", .indeterminate = true, .size = sz[0], .label_font_size = sz[1] }).mount(f.scope, f.cx));
        try std.testing.expectEqual(sz[0], cb.children.items[0].style.width.px);
        try std.testing.expectEqual(sz[0], cb.children.items[0].style.height.px);
        try std.testing.expectEqual(sz[0] * 0.75, checkmarkOf(cb).style.width.px);
        try std.testing.expectEqual(sz[0] * 0.75, checkmarkOf(cb).style.height.px);
        try std.testing.expectEqual(sz[0], indetOf(cb).style.width.px);
        try std.testing.expectEqual(sz[0] * 0.75, indetOf(cb).children.items[0].style.width.px);
        try std.testing.expectEqual(sz[1], findText(cb, "b").?.getText().?.font_size);
    }
    // Sizes follow a signal source.
    const edge = try f.scope.createSignal(?f32, 14);
    const live = try f.add(try Checkbox(.{ .size = edge }).mount(f.scope, f.cx));
    try std.testing.expectEqual(@as(f32, 14), live.children.items[0].style.width.px);
    edge.set(null);
    try std.testing.expectEqual(t.size.checkbox, live.children.items[0].style.width.px);
}


// ── RadioOption.description ──

const radio_text_render = @import("../../core/render_engine/text_render.zig");

fn nodeCount(n: *Node) usize {
    var total: usize = 1;
    for (n.children.items) |c| total += nodeCount(c);
    return total;
}

/// Shown text of the option's described column (label, description).
fn describedColumn(opt: *Node) *Node {
    return opt.children.items[2];
}

test "RadioGroup: description — a second line under the label (xs, fg-secondary), top-aligned, the a11y description" {
    const f = try Fixture.init();
    defer f.deinit();
    const t = f.cx.tokens;
    const opts = [_]RadioOption{
        .{ .value = "nginx", .label = "nginx", .description = "Check the config before restarting: nginx -t" },
        .{ .value = "apache", .label = "apache" },
    };
    const group = try f.add(try RadioGroup(.{ .options = &opts, .value = "nginx" }).mount(f.scope, f.cx));
    f.cx.layout();
    const described = option(group, 0);
    const plain = option(group, 1);
    // [circle, one-line label (hidden), column [label, description]].
    try std.testing.expectEqual(@as(usize, 3), described.children.items.len);
    try std.testing.expect(described.children.items[1].style.display == .none);
    const column = describedColumn(described);
    try std.testing.expectEqual(@as(usize, 2), column.children.items.len);
    const label = column.children.items[0];
    const about = column.children.items[1];
    try std.testing.expectEqualStrings("nginx", label.getText().?.content);
    try std.testing.expectEqualStrings("Check the config before restarting: nginx -t", about.getText().?.content);
    const about_props = radio_text_render.resolveNodeLogicalTextProps(about).?;
    try std.testing.expectEqual(t.tokens.font_size.xs, about_props.font_size);
    try std.testing.expect(Color.eql(t.tokens.color.fg_secondary, about_props.color));
    try std.testing.expectEqual(core.TextWrap.word, about.getText().?.wrap);
    try std.testing.expect(Color.eql(t.tokens.color.fg_primary, radio_text_render.resolveNodeLogicalTextProps(label).?.color));
    // Label over description (gap space50), the row aligned to the top, the circle centred on the
    // label's first line.
    try std.testing.expectEqual(core.AlignItems.start, described.style.align_items);
    const lr = label.globalRect();
    const ar = about.globalRect();
    try std.testing.expectApproxEqAbs(lr.y + lr.h + t.tokens.space.space50, ar.y, 0.01);
    const circle = described.children.items[0].globalRect();
    try std.testing.expectApproxEqAbs(lr.y + lr.h / 2, circle.y + circle.h / 2, 0.01);
    try std.testing.expect(described.rectFromWorldOrFallback().h > plain.rectFromWorldOrFallback().h);
    // a11y: name = label, description = the description; a plain option has none.
    const a = described.behavior.interaction.a11y.?;
    try std.testing.expectEqualStrings("nginx", a.label.?);
    try std.testing.expectEqualStrings("Check the config before restarting: nginx -t", a.description.?);
    try std.testing.expect(plain.behavior.interaction.a11y.?.description == null);
}

test "RadioGroup: an option without description keeps its tree and size (static and signal options)" {
    const f = try Fixture.init();
    defer f.deinit();
    const before = [_]RadioOption{ .{ .value = "a", .label = "Alpha" }, .{ .value = "b", .label = "Beta" } };
    const mixed = [_]RadioOption{ .{ .value = "a", .label = "Alpha" }, .{ .value = "b", .label = "Beta", .description = "second line" } };
    const sig_plain = try f.scope.createSignal([]const RadioOption, &before);
    const sig_mixed = try f.scope.createSignal([]const RadioOption, &mixed);
    const groups = [_]*Node{
        try f.add(try RadioGroup(.{ .options = &before }).mount(f.scope, f.cx)),
        try f.add(try RadioGroup(.{ .options = &mixed }).mount(f.scope, f.cx)),
        try f.add(try RadioGroup(.{ .options = sig_plain }).mount(f.scope, f.cx)),
        try f.add(try RadioGroup(.{ .options = sig_mixed }).mount(f.scope, f.cx)),
    };
    f.cx.layout();
    const ref = option(groups[0], 0);
    for (groups) |g| {
        const o = option(g, 0); // "Alpha", no description in every group
        // [circle [dot], label]: no hidden label, no column, no anchors.
        try std.testing.expectEqual(@as(usize, 2), o.children.items.len);
        try std.testing.expectEqual(@as(usize, 4), nodeCount(o));
        try std.testing.expectEqual(core.AlignItems.center, o.style.align_items);
        try std.testing.expectApproxEqAbs(ref.rectFromWorldOrFallback().w, o.rectFromWorldOrFallback().w, 0.01);
        try std.testing.expectApproxEqAbs(ref.rectFromWorldOrFallback().h, o.rectFromWorldOrFallback().h, 0.01);
        try std.testing.expectEqual(ref.children.items[0].style.margin, o.children.items[0].style.margin);
    }
    // Whole groups: the same count of nodes as before descriptions existed (2 rows x 4; a signal
    // list adds its two anchors).
    try std.testing.expectEqual(@as(usize, 9), nodeCount(groups[0]));
    try std.testing.expectEqual(@as(usize, 11), nodeCount(groups[2]));
}

test "RadioGroup: description is part of the key — a change rebuilds the option" {
    const f = try Fixture.init();
    defer f.deinit();
    const plain = [_]RadioOption{.{ .value = "a", .label = "A" }};
    const one = [_]RadioOption{.{ .value = "a", .label = "A", .description = "one" }};
    const two = [_]RadioOption{.{ .value = "a", .label = "A", .description = "two" }};
    const options = try f.scope.createSignal([]const RadioOption, &plain);
    const group = try f.add(try RadioGroup(.{ .options = options, .value = "a" }).mount(f.scope, f.cx));
    try std.testing.expectEqual(@as(usize, 2), option(group, 0).children.items.len);
    options.set(&one);
    const first = option(group, 0);
    try std.testing.expectEqualStrings("one", describedColumn(first).children.items[1].getText().?.content);
    try std.testing.expectEqualStrings("one", first.behavior.interaction.a11y.?.description.?);
    options.set(&two);
    const second = option(group, 0);
    try std.testing.expect(second != first);
    try std.testing.expectEqualStrings("two", describedColumn(second).children.items[1].getText().?.content);
    options.set(&plain);
    try std.testing.expectEqual(@as(usize, 2), option(group, 0).children.items.len);
    try std.testing.expect(option(group, 0).behavior.interaction.a11y.?.description == null);
}

test "RadioGroup: a disabled described option dims its description" {
    const f = try Fixture.init();
    defer f.deinit();
    const t = f.cx.tokens;
    const opts = [_]RadioOption{.{ .value = "a", .label = "A", .description = "why", .disabled = true }};
    const group = try f.add(try RadioGroup(.{ .options = &opts }).mount(f.scope, f.cx));
    const column = describedColumn(option(group, 0));
    try std.testing.expect(Color.eql(t.tokens.color.fg_disabled, radio_text_render.resolveNodeLogicalTextProps(column.children.items[1]).?.color));
    try std.testing.expect(Color.eql(t.tokens.color.fg_disabled, radio_text_render.resolveNodeLogicalTextProps(column.children.items[0]).?.color));
}

test "radio_group(description): mount 在任意分配点失败时不泄漏（sweep）" {
    try @import("../oom_sweep.zig").sweepMount("radio_group(description)", struct {
        const opts = [_]RadioOption{ .{ .value = "a", .label = "A", .description = "first line under A" }, .{ .value = "b", .label = "B" } };
        fn m(scope: *Scope, cx: *Cx) anyerror!?*Node {
            const o = try scope.createSignal([]const RadioOption, &opts);
            return try RadioGroup(.{ .options = o, .value = "a" }).mount(scope, cx);
        }
    }.m);
}

test "radio_group(description, static): mount 在任意分配点失败时不泄漏（sweep）" {
    try @import("../oom_sweep.zig").sweepMount("radio_group(description static)", struct {
        fn m(scope: *Scope, cx: *Cx) anyerror!?*Node {
            const opts = [_]RadioOption{ .{ .value = "a", .label = "A", .description = "first line under A" }, .{ .value = "b", .label = "B", .disabled = true } };
            return try RadioGroup(.{ .options = &opts, .value = "a" }).mount(scope, cx);
        }
    }.m);
}
