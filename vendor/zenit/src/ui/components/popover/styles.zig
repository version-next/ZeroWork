/// Popover, style layer
///
/// Floating panel appearance declaration; overlay lifecycle / portal / positioning logic in
/// mod.zig.
const core = @import("../../core.zig");
const theme = core.theme;
const Color = core.Color;
const Border = core.Border;
const Shadow = core.Shadow;

/// Panel corner radius, border.radius and hit/clip shape share same scalar
pub fn popoverRadius(t: *const theme.ThemeTokens) f32 {
    return t.tokens.radius.panel;
}

pub fn popoverContentBackground(t: *const theme.ThemeTokens) Color {
    return t.tokens.color.bg_primary;
}

pub fn popoverContentBorder(t: *const theme.ThemeTokens) Border {
    return .{
        .width = 1,
        .overlay = true,
        .color = t.tokens.color.border,
        .radius = popoverRadius(t),
    };
}

/// Main shadow layer, token shadow.md
pub fn popoverKeyShadow(t: *const theme.ThemeTokens) Shadow {
    return t.tokens.shadow.md;
}

/// Recolor the default chrome, preserving explicit caller overrides and all
/// dimensions managed by the positioner.
pub fn updateChromeTheme(node: *core.Node, before: *const theme.ThemeTokens, after: *const theme.ThemeTokens) void {
    if (Color.eql(node.getBackground(), popoverContentBackground(before))) {
        node.setBackground(popoverContentBackground(after));
    }
    if (Color.eql(node.style.border.color, before.tokens.color.border)) {
        node.setBorderColor(after.tokens.color.border);
    }
    if (node.style.ext) |ext| {
        if (ext.shadow_count == 1 and @import("std").meta.eql(ext.shadows[0], popoverKeyShadow(before))) {
            ext.setShadow(popoverKeyShadow(after));
            node.markRenderDirty();
        }
    }
}
