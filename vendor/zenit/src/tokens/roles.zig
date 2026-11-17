//! Component role tokens read by Zenit's built-in recipes, with their default aliases.
//!
//! The default theme declares every role explicitly (src/tokens/default.json). A theme that
//! predates a role and omits it still generates a provider with the role: the resolver adds the
//! missing role as an alias of its `target` (see resolve.zig `defaultRoles`). The target is the
//! semantic token the recipe read before the role existed, so such a theme keeps its appearance.
//! A theme that declares a role (either spelling, `a_b` or `a-b`) is never touched, and a role
//! whose target the theme lacks is left out.
//!
//! Order matters only when a role targets another role: list the target first.
pub const Role = struct {
    /// Unified consumption path, e.g. `color.checkbox_fg`.
    path: []const u8,
    /// Unified path of the default alias target, e.g. `color.fg_inverse`.
    target: []const u8,
};

pub const component_roles = [_]Role{
    // Button tones (ControlShell Tone recipe).
    .{ .path = "color.button_primary_bg", .target = "color.accent" },
    .{ .path = "color.button_primary_fg", .target = "color.fg_inverse" },
    .{ .path = "color.button_primary_hover", .target = "color.accent_hover" },
    .{ .path = "color.button_primary_pressed", .target = "color.accent_pressed" },
    .{ .path = "color.button_secondary_bg", .target = "color.bg_primary" },
    .{ .path = "color.button_secondary_fg", .target = "color.fg_primary" },
    .{ .path = "color.button_danger_bg", .target = "color.danger" },
    .{ .path = "color.button_danger_fg", .target = "color.fg_inverse" },
    .{ .path = "color.button_danger_hover", .target = "color.danger_hover" },
    .{ .path = "color.button_danger_pressed", .target = "color.danger_pressed" },
    // Checkbox / Radio indicator.
    .{ .path = "color.checkbox_bg", .target = "color.bg_primary" },
    .{ .path = "color.checkbox_border", .target = "color.border_strong" },
    .{ .path = "color.checkbox_checked_bg", .target = "color.accent" },
    .{ .path = "color.checkbox_fg", .target = "color.fg_inverse" },
    .{ .path = "color.checkbox_disabled_bg", .target = "color.disabled_bg" },
    .{ .path = "color.checkbox_disabled_border", .target = "color.border" },
    .{ .path = "color.checkbox_disabled_checked_bg", .target = "color.disabled_bg" },
    .{ .path = "color.checkbox_disabled_fg", .target = "color.fg_disabled" },
    // Switch.
    .{ .path = "color.switch_track_on", .target = "color.accent" },
    .{ .path = "color.switch_thumb_on", .target = "color.fg_inverse" },
    .{ .path = "color.switch_disabled_track_on", .target = "color.border" },
    .{ .path = "color.switch_disabled_track_off", .target = "color.border" },
    .{ .path = "color.switch_disabled_thumb_on", .target = "color.bg_secondary" },
    .{ .path = "color.switch_disabled_thumb_off", .target = "color.bg_secondary" },
    // Slider.
    .{ .path = "color.range_track", .target = "color.bg_tertiary" },
    .{ .path = "color.range_fill", .target = "color.accent" },
    .{ .path = "color.range_hover", .target = "color.accent_hover" },
    .{ .path = "color.range_drag", .target = "color.accent_hover" },
    .{ .path = "color.range_thumb", .target = "color.bg_primary" },
    .{ .path = "color.range_disabled", .target = "color.fg_disabled" },
    .{ .path = "color.range_disabled_thumb", .target = "color.fg_disabled" },
    // Progress.
    .{ .path = "color.progress_fill", .target = "color.accent" },
    .{ .path = "color.progress_success", .target = "color.success" },
    .{ .path = "color.progress_warning", .target = "color.warning" },
    .{ .path = "color.progress_error", .target = "color.danger" },
    // Focus fill for focus-fill styling modes.
    .{ .path = "color.bg_focus", .target = "color.bg_active" },
};
