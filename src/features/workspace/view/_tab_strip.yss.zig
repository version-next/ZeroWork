// GENERATED FILE, do not edit: generated from tab_strip.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! 页签条（design-r3 稿 3，Island B v3 `ZW4 / Tab`）的布局与页签面：只写我们自己的盒子（单元、页签面、标题、
//! 计数、类型图标、连接状态点、⌘ 序号、分隔线）。关闭钮、新建按钮、“⌄ n”溢出按钮、Tooltip、Menu 都是
//! zenit 原生组件，这里不写它们的外观，只给它们排位置。
//!
//! 尺寸：页签条高 33；非激活页签面高 30（离岛 3），激活页签面高 33；连接表面随激活页签位移，在窗口背景层连续绘制。
//! 页签面内：左 10 · 类型图标 14 · 6 · 标题（组页签：组名 · 4 · 成员数）· 关闭槽 20 · 右 2。
const ui = @import("ui");
const std = @import("std");
const m = @import("../model/tab_strip.zig");
const tab_styles = @import("workspace_tab_styles.zig");

pub const height: f32 = 33;
pub const surface_height: f32 = 30;
pub const outer_inset: f32 = 2;
/// 关闭槽：原生 xs 图标按钮（20 × 20）。
pub const close_slot: f32 = 20;

/// 整条：单元首尾相接（gap 0），底对齐到岛的上沿；“⌄ n”与“+”跟在最后一个页签后面。
pub const strip = ui.previewCss("src/features/workspace/view/tab_strip.yss", "strip", @embedFile("tab_strip.yss"), .{ .direction = .row, .align_items = .end, .height = 33, .gap = 0, .flex_shrink = 0, });
/// 页签区：拖动时的插入缝绝对定位在它里面。
pub const viewport = ui.previewCss("src/features/workspace/view/tab_strip.yss", "viewport", @embedFile("tab_strip.yss"), .{ .direction = .row, .align_items = .end, .height = 33, .gap = 0, .flex_shrink = 0, });
/// “⌄ n”：原生 ghost sm 按钮，与非激活页签面同一条中线（底部留 3 + (30 - 24) / 2）；固定 56 宽的槽（`tab_strip_layout.overflow_reserve`），按钮靠左。
pub const overflow = ui.previewCss("src/features/workspace/view/tab_strip.yss", "overflow", @embedFile("tab_strip.yss"), .{ .width = 56, .direction = .row, .align_items = .end, .height = .fill, .padding = .{ .top = 0, .right = 0, .bottom = 6, .left = 4 }, .flex_shrink = 0, });
/// “+”（Pencil nCMeb）：原生 ghost sm 图标按钮，同上的中线；有页签时与前面相距 4。
pub const NewSlot = ui.previewCva("src/features/workspace/view/tab_strip.yss", "NewSlot", @embedFile("tab_strip.yss"), .{ .base = .{ .direction = .row, .align_items = .end, .height = .fill, .padding = .{ .top = 0, .right = 0, .bottom = 6, .left = 0 }, .flex_shrink = 0, }, .variants = .{ .after_tabs = .{ .false = .{ }, .true = .{ .padding = .{ .top = 0, .right = 0, .bottom = 6, .left = 4 }, }, }, }, .defaults = .{ .after_tabs = false, }, });

/// 一个页签单元：宽度来自布局（88–200，组 160–240），两侧各 2 的内边距也是这个页签的命中区。
pub fn cell(width: f32, _: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .{ .px = width }, .height = .{ .px = height }, .flex_shrink = 0, .hit_behavior = .@"opaque" };
}
/// Tooltip 的触发区铺满单元；非激活面在岛上缘之前停 3pt。
pub const trigger = ui.previewCss("src/features/workspace/view/tab_strip.yss", "trigger", @embedFile("tab_strip.yss"), .{ .width = .fill, .height = .fill, .direction = .row, .align_items = .start, .padding = .{ .y = 0, .x = 2 }, });
/// A cell owns its leading separator, centered on the inactive surfaces.
pub const divider = ui.previewCss("src/features/workspace/view/tab_strip.yss", "divider", @embedFile("tab_strip.yss"), .{ .position = .absolute, .inset = ui.Inset{ .left = .{ .px = 0 }, .top = .{ .px = 8 } }, .width = 1, .height = 14, .background = ui.tokenRef(.color, "border"), .hit_behavior = .pass_through, });

/// 页签面（Pencil SHfTh：普通 / 悬停 / 按下 / 激活；YLyJw 拖起；拖到另一个页签上合组时的描边）。
pub fn surface(look: m.Look, t: *const ui.ThemeTokens) ui.BoxStyle {
    const c = t.tokens.color;
    const width = @max(0, look.width - 2 * outer_inset);
    const active_radius = tab_styles.attachedRadius(t.tokens.radius.island);
    const hover_radius = @max(0, active_radius - (height - surface_height));
    var s: ui.BoxStyle = .{ .cursor = .grab, .width = .{ .px = width }, .height = .{ .px = surface_height }, .direction = .row, .align_items = .center, .padding = .{ .left = 10, .right = 2 }, .gap = 0, .flex_shrink = 0, .background = ui.Color.TRANSPARENT, .border = .{ .radius = hover_radius } };
    switch (look.state) {
        .normal => {},
        .hover => s.background = c.bg_hover,
        .press => s.background = c.bg_active,
        .active => {
            s.height = .{ .px = height };
            // Content stays on the inactive surfaces' centre line: the 3 below joins the island.
            s.padding = .{ .left = 10, .right = 2, .bottom = height - surface_height };
            s.border = .{ .radius = 0 };
            s.corner_radii = .{ .each = .{ active_radius, active_radius, 0, 0 } };
        },
    }
    if (look.lifted) {
        s.height = .{ .px = surface_height };
        s.background = c.zw_island_focus;
        s.corner_radii = .{ .each = .{ 8, 8, 8, 8 } };
        s.border = .{ .width = 1, .color = c.border, .radius = 8 };
        s.shadow = t.tokens.shadow.lg;
        s.z_index = 10;
    }
    if (look.drop) s.outline = .{ .color = c.accent, .width = 2, .offset = -2 };
    return s;
}

/// 类型图标槽（14 × 14），连接状态点绝对定位在它右上角。
pub const icon_slot = ui.previewCss("src/features/workspace/view/tab_strip.yss", "icon_slot", @embedFile("tab_strip.yss"), .{ .width = 14, .height = 14, .margin = .{ .top = 0, .right = 6, .bottom = 0, .left = 0 }, .flex_shrink = 0, .align_items = .center, .justify = .center, });
/// 类型图标：未读的后台页签轻跳（`bounce` 是向上的位移）。颜色由 `tint` 给（环境色 / 用户色 / 状态色）。
pub fn typeIcon(bounce: f32, _: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .{ .px = 14 }, .height = .{ .px = 14 }, .translate_y = bounce };
}
pub fn typeTint(tint: ui.Color, _: *const ui.ThemeTokens) ui.Color {
    return tint;
}
/// 连接状态点：6 × 6，压在图标右上角，描一圈浮层色的边。
pub fn dot(color: ui.Color, t: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .position = .absolute, .inset = .{ .left = .{ .px = 10 }, .top = .{ .px = -2 } }, .width = .{ .px = 6 }, .height = .{ .px = 6 }, .background = color, .border = .{ .width = 1, .color = t.tokens.color.bg_tertiary, .radius = 3 }, .hit_behavior = .pass_through };
}

/// 标题：12，普通态次要墨色，悬停 / 按下 / 激活主墨色；激活 600（宽度按 600 预留，激活时不截断）。
pub fn title(look: m.Look, t: *const ui.ThemeTokens) ui.TextStyle {
    const c = t.tokens.color;
    return .{ .font_size = 12, .font_weight = if (look.state == .active) 600 else 400, .color = if (look.state == .normal and !look.lifted) c.fg_secondary else c.fg_primary, .line_height = 1.5, .text_overflow = .ellipsis, .selectable = false };
}
pub fn titleBox(width: f32, _: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .{ .px = width }, .height = .{ .px = 16 }, .overflow_hidden = true, .flex_shrink = 0 };
}
/// 组页签的成员数“(n)”：跟在（截断后的）组名后面 4，从不截断。
pub fn count(look: m.Look, t: *const ui.ThemeTokens) ui.TextStyle {
    var s = title(look, t);
    s.text_overflow = .clip;
    return s;
}
pub fn countBox(width: f32, _: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .{ .px = width }, .height = .{ .px = 16 }, .margin = .{ .left = 4 }, .flex_shrink = 0 };
}
/// 标题之后、关闭槽之前的空白。
pub const spacer = ui.previewCss("src/features/workspace/view/tab_strip.yss", "spacer", @embedFile("tab_strip.yss"), .{ .width = .fill, .height = 1, .flex = 1, .min_width = 0, });

/// 关闭槽（20 × 20）：悬停 / 键盘焦点在页签上时出现，否则透明但占位（标题不会因此重排）；按住 ⌘ 时换成序号。
pub const CloseSlot = ui.previewCva("src/features/workspace/view/tab_strip.yss", "CloseSlot", @embedFile("tab_strip.yss"), .{ .base = .{ .width = 20, .height = 20, .flex_shrink = 0, .align_items = .center, .justify = .center, }, .variants = .{ .hidden = .{ .false = .{ }, .true = .{ .opacity = 0, .hit_behavior = .pass_through, }, }, }, .defaults = .{ .hidden = false, }, });
/// ⌘ 序号：10 / 500 次要墨色，右对齐到关闭槽。
pub const ordinal_box = ui.previewCss("src/features/workspace/view/tab_strip.yss", "ordinal_box", @embedFile("tab_strip.yss"), .{ .position = .absolute, .inset = ui.Inset{ .right = .{ .px = 2 }, .top = .{ .px = 7 } }, .width = 20, .height = 16, .align_items = .center, .justify = .end, .hit_behavior = .pass_through, });
pub const ordinal = ui.previewCss("src/features/workspace/view/tab_strip.yss", "ordinal", @embedFile("tab_strip.yss"), .{ .font_size = 10, .font_weight = 500, .color = ui.tokenRef(.color, "fg-secondary"), .text_overflow = .clip, .selectable = false, });

/// 拖动时的插入缝（Figma 259:241008）：4 宽、与页签条同高、圆角 2，强调色。
pub fn dragGap(x: f32, t: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .position = .absolute, .inset = .{ .left = .{ .px = 0 }, .top = .{ .px = 0 } }, .translate_x = x, .width = .{ .px = 4 }, .height = .{ .px = height }, .background = t.tokens.color.accent, .border = .{ .radius = 2 }, .hit_behavior = .pass_through };
}

//# yix-map tab_strip.yss
