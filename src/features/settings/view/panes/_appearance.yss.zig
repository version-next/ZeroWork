// GENERATED FILE, do not edit: generated from appearance.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! 外观与主题面板（P3 3e 外观包）的样式：主题条、主题卡片（自定义内容：色板 + 名称 + 原生 `W.Radio`）、ANSI 色板、
//! 背景图片的身份行与成对的选择框、滑块行、终端预览与工作区缩略预览。控件全部是原生组件（默认外观，不覆盖）；
//! 这里只给布局盒子、`W.Pressable` 根（它没有自己的外观）与文字定样式。颜色：界面色用 token；**主题的预览色是数据**
//! （每张卡片画的是那个主题自己的底色 / 强调色 / ANSI 色），经下面的 `styleBy` 函数按主题记录取色。
//! 几何沿用旧 `appearance_view` / `appearance_styles`（Island B v3：`J91kn` 主题卡片、`EGpsf` 预览、`zCqTq` 终端面）。
const ui = @import("ui");
const m = @import("../../model/view_model.zig");

fn rgba(value: u32) ui.Color {
    return ui.Color.rgba(@intCast(value >> 24), @intCast((value >> 16) & 255), @intCast((value >> 8) & 255), @intCast(value & 255));
}

// ── 主题 ──

/// 主题面板的正文卡片：与其它面板的正文同一张卡（内边距 [0, 14]，圆角 12，窗面静止底色）。
pub const theme_body = ui.previewCss("src/features/settings/view/panes/appearance.yss", "theme_body", @embedFile("appearance.yss"), .{ .width = .fill, .direction = .column, .align_items = .stretch, .gap = 0, .padding = .{ .y = 0, .x = 14 }, .corner_radius = 12, .background = ui.tokenRef(.color, "zw-window-rest"), .overflow = .hidden, });
/// 主题条（`settings.theme.strip`）：横向滚动，高 81，上 6 下 10。
pub const theme_strip = ui.previewCss("src/features/settings/view/panes/appearance.yss", "theme_strip", @embedFile("appearance.yss"), .{ .width = .fill, .height = 81, .min_width = 0, .flex_shrink = 0, .margin = .{ .top = 6, .right = 0, .bottom = 10, .left = 0 }, });
pub const theme_row = ui.previewCss("src/features/settings/view/panes/appearance.yss", "theme_row", @embedFile("appearance.yss"), .{ .width = .fit, .height = 81, .direction = .row, .gap = 8, });
/// 一张卡片的位置（导入的主题外面多一层原生 `W.Menu`）。
pub const theme_tile = ui.previewCss("src/features/settings/view/panes/appearance.yss", "theme_tile", @embedFile("appearance.yss"), .{ .width = 150, .height = 81, .flex_shrink = 0, .direction = .column, });
/// 主题卡片（`J91kn`）：150 × 81，色板 58 在上、名称行在下（间距 5）；悬停 0.92、按下 0.85 透明度。
pub const ThemeCard = ui.previewCva("src/features/settings/view/panes/appearance.yss", "ThemeCard", @embedFile("appearance.yss"), .{ .base = .{ .width = 150, .height = 81, .flex_shrink = 0, .direction = .column, .align_items = .stretch, .gap = 5, .padding = 0, .corner_radius = 8, .background = ui.Color.TRANSPARENT, .transition = ui.transition("opacity 120ms ease-out"), ._hover = .{ .opacity = 0.92, }, ._active = .{ .opacity = 0.85, }, }, .variants = .{ .off = .{ .false = .{ }, .true = .{ .opacity = 0.5, ._hover = .{ .opacity = 0.5, }, ._active = .{ .opacity = 0.5, }, }, }, }, .defaults = .{ .off = false, }, });
/// 名称行：名称（11.5 / 600，单行省略）+ 原生单选圆点。
pub const theme_caption = ui.previewCss("src/features/settings/view/panes/appearance.yss", "theme_caption", @embedFile("appearance.yss"), .{ .width = .fill, .height = 18, .flex_shrink = 0, .direction = .row, .align_items = .center, .gap = 4, });
pub const theme_name = ui.previewCss("src/features/settings/view/panes/appearance.yss", "theme_name", @embedFile("appearance.yss"), .{ .font_size = 11.5, .font_weight = 600, .line_height = 18.0 / 11.5, .color = ui.tokenRef(.color, "fg-primary"), .wrap = .none, .text_overflow = .ellipsis, });
pub const theme_name_box = ui.previewCss("src/features/settings/view/panes/appearance.yss", "theme_name_box", @embedFile("appearance.yss"), .{ .width = .fill, .flex = 1, .min_width = 0, });
/// 主题条下的一行：主题数说明 + “预览中” + 删除当前主题 / 导入。
pub const theme_actions = ui.previewCss("src/features/settings/view/panes/appearance.yss", "theme_actions", @embedFile("appearance.yss"), .{ .width = .fill, .min_height = 30, .flex_shrink = 0, .direction = .row, .align_items = .center, .gap = 8, .padding = .{ .top = 4, .right = 0, .bottom = 0, .left = 0 }, });
pub const note = ui.previewCss("src/features/settings/view/panes/appearance.yss", "note", @embedFile("appearance.yss"), .{ .font_size = 11, .font_weight = 400, .line_height = 16.0 / 11.0, .color = ui.tokenRef(.color, "zw-fg-supporting"), .wrap = .word, });
pub const fill_text = ui.previewCss("src/features/settings/view/panes/appearance.yss", "fill_text", @embedFile("appearance.yss"), .{ .width = .fill, .flex = 1, .min_width = 0, });
pub const error_note = ui.previewCss("src/features/settings/view/panes/appearance.yss", "error_note", @embedFile("appearance.yss"), .{ .font_size = 11, .font_weight = 400, .line_height = 16.0 / 11.0, .color = ui.tokenRef(.color, "danger"), .wrap = .word, });
/// 背景准备的状态行：失败时用危险色。
pub const StateNote = ui.previewCva("src/features/settings/view/panes/appearance.yss", "StateNote", @embedFile("appearance.yss"), .{ .base = .{ .font_size = 11, .font_weight = 400, .line_height = 16.0 / 11.0, .color = ui.tokenRef(.color, "zw-fg-supporting"), .wrap = .word, }, .variants = .{ .failed = .{ .false = .{ }, .true = .{ .color = ui.tokenRef(.color, "danger"), }, }, }, .defaults = .{ .failed = false, }, });
/// 可能整行换形态的块（字重行、缩略预览）的外层：不占额外空间。
pub const weight_body = ui.previewCss("src/features/settings/view/panes/appearance.yss", "weight_body", @embedFile("appearance.yss"), .{ .width = .fill, .direction = .column, .gap = 0, .min_width = 0, .flex_shrink = 0, });
/// 提示行（图标 + 文字），高 28。
pub const notice = ui.previewCss("src/features/settings/view/panes/appearance.yss", "notice", @embedFile("appearance.yss"), .{ .width = .fill, .min_height = 28, .flex_shrink = 0, .direction = .row, .align_items = .center, .gap = 6, });
pub const notice_icon = ui.previewCss("src/features/settings/view/panes/appearance.yss", "notice_icon", @embedFile("appearance.yss"), .{ .width = 16, .height = 16, .flex_shrink = 0, .icon_color = ui.tokenRef(.color, "zw-fg-supporting"), });
pub const notice_error_icon = ui.previewCss("src/features/settings/view/panes/appearance.yss", "notice_error_icon", @embedFile("appearance.yss"), .{ .width = 16, .height = 16, .flex_shrink = 0, .icon_color = ui.tokenRef(.color, "danger"), });

/// 主题卡片的色板（数据色：主题终端底色；选中时 2pt 强调色描边，否则 1pt 边框色）。
pub fn swatch(card: m.ThemeCard, t: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 58 }, .direction = .column, .padding = ui.Padding.all(8), .gap = 4, .background = rgba(card.record.theme.bg), .border = .{ .width = if (card.selected) 2 else 1, .color = if (card.selected) t.tokens.color.accent else t.tokens.color.border, .radius = 8 }, .flex_shrink = 0 };
}
/// 色板里的三条：强调色 40 宽、次表面色填满、次表面色 30 宽（高 4，圆角 2）。
pub fn swatchAccent(card: m.ThemeCard, _: *const ui.ThemeTokens) ui.BoxStyle {
    return bar(40, card.record.ui_tokens.accent);
}
pub fn swatchFill(card: m.ThemeCard, _: *const ui.ThemeTokens) ui.BoxStyle {
    return bar(null, card.record.ui_tokens.surface_2);
}
pub fn swatchShort(card: m.ThemeCard, _: *const ui.ThemeTokens) ui.BoxStyle {
    return bar(30, card.record.ui_tokens.surface_2);
}
fn bar(width: ?f32, color: u32) ui.BoxStyle {
    return .{ .width = if (width) |px| .{ .px = px } else .fill(), .height = .{ .px = 4 }, .background = rgba(color), .border = .{ .radius = 2 }, .flex_shrink = 0 };
}

/// ANSI 色板（`settings.theme.ansi`）：当前主题的终端底色，内边距 8，圆角 8。
pub fn ansiPanel(colors: m.TerminalColors, _: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .direction = .column, .gap = 6, .padding = ui.Padding.all(8), .margin = .{ .top = 4, .bottom = 6 }, .background = rgba(colors.background), .border = .{ .radius = 8 }, .flex_shrink = 0 };
}
pub fn ansiTitle(colors: m.TerminalColors, _: *const ui.ThemeTokens) struct { font_size: f32, line_height: f32, color: ui.Color } {
    return .{ .font_size = 10, .line_height = 1.4, .color = rgba(colors.foreground) };
}
pub const ansi_strip = ui.previewCss("src/features/settings/view/panes/appearance.yss", "ansi_strip", @embedFile("appearance.yss"), .{ .width = .fill, .height = 12, .direction = .row, .gap = 4, .flex_shrink = 0, });
pub fn ansiCell(color: u32, _: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .flex = 1, .min_width = 0, .height = .fill(), .background = rgba(color), .border = .{ .radius = 2 } };
}

// ── 设置行里的布局 ──

/// 行右侧的控件组（滑块 + 输入框）：350 宽，间距 12。
pub const slider_group = ui.previewCss("src/features/settings/view/panes/appearance.yss", "slider_group", @embedFile("appearance.yss"), .{ .width = 350, .height = 32, .flex_shrink = 0, .direction = .row, .align_items = .center, .gap = 12, });
pub const slider_box = ui.previewCss("src/features/settings/view/panes/appearance.yss", "slider_box", @embedFile("appearance.yss"), .{ .width = .fill, .flex = 1, .min_width = 0, .direction = .row, .align_items = .center, .padding = .{ .y = 0, .x = 8 }, });
/// 背景图片的成对选择框（轮播方式 + 切换间隔、图片适配 + 图片对齐）：两列并排，间距 16。
pub const pair = ui.previewCss("src/features/settings/view/panes/appearance.yss", "pair", @embedFile("appearance.yss"), .{ .width = .fill, .direction = .row, .gap = 16, .padding = .{ .y = 10, .x = 0 }, .min_width = 0, .flex_shrink = 0, });
pub const pair_field = ui.previewCss("src/features/settings/view/panes/appearance.yss", "pair_field", @embedFile("appearance.yss"), .{ .width = .fill, .flex = 1, .min_width = 0, .direction = .row, .align_items = .center, .gap = 12, });
/// 成对选择框的标签列：76 宽（标签 + “?”）。
pub const pair_label = ui.previewCss("src/features/settings/view/panes/appearance.yss", "pair_label", @embedFile("appearance.yss"), .{ .width = 76, .flex_shrink = 0, .direction = .row, .align_items = .center, .gap = 4, });
pub const pair_control = ui.previewCss("src/features/settings/view/panes/appearance.yss", "pair_control", @embedFile("appearance.yss"), .{ .width = .fill, .flex = 1, .min_width = 0, .direction = .row, .align_items = .center, });
/// 图片对齐的九宫格（原生单选）：三行三列，间距 4。
pub const alignment_grid = ui.previewCss("src/features/settings/view/panes/appearance.yss", "alignment_grid", @embedFile("appearance.yss"), .{ .direction = .column, .gap = 4, .padding = 4, });
pub const alignment_row = ui.previewCss("src/features/settings/view/panes/appearance.yss", "alignment_row", @embedFile("appearance.yss"), .{ .direction = .row, .gap = 4, });
pub const alignment_cell = ui.previewCss("src/features/settings/view/panes/appearance.yss", "alignment_cell", @embedFile("appearance.yss"), .{ .width = 32, .height = 32, .flex_shrink = 0, .direction = .row, .align_items = .center, .justify = .center, .corner_radius = 6, .background = ui.Color.TRANSPARENT, ._hover = .{ .background = ui.tokenRef(.color, "bg-hover"), }, ._active = .{ .background = ui.tokenRef(.color, "bg-active"), }, });
/// 应用图标行的单选组外层（原生 `W.RadioGroup`，默认外观）。
pub const radio_slot = ui.previewCss("src/features/settings/view/panes/appearance.yss", "radio_slot", @embedFile("appearance.yss"), .{ .flex_shrink = 0, .direction = .row, .align_items = .center, });

// ── 背景图片 ──

/// 背景身份行（`settings.background.identity`）：缩略图 72 × 48 + 文件名 / 状态 + 选择 / 移除，高 68。
pub const identity = ui.previewCss("src/features/settings/view/panes/appearance.yss", "identity", @embedFile("appearance.yss"), .{ .width = .fill, .height = 68, .flex_shrink = 0, .min_width = 0, .direction = .row, .align_items = .center, .gap = 10, });
/// 缩略图按钮（`settings.materials.preview.open`，进入全窗口预览）：72 × 48，圆角 5，裁切。
pub const Thumbnail = ui.previewCva("src/features/settings/view/panes/appearance.yss", "Thumbnail", @embedFile("appearance.yss"), .{ .base = .{ .width = 72, .height = 48, .flex_shrink = 0, .position = .relative, .direction = .row, .align_items = .center, .justify = .center, .corner_radius = 5, .overflow = .hidden, .background = ui.tokenRef(.color, "bg-primary"), .border_width = 1, .border_color = ui.tokenRef(.color, "border"), .transition = ui.transition("opacity 120ms ease-out"), ._hover = .{ .opacity = 0.9, }, }, .variants = .{ .off = .{ .false = .{ }, .true = .{ .opacity = 0.5, ._hover = .{ .opacity = 0.5, }, }, }, }, .defaults = .{ .off = false, }, });
pub const thumbnail_icon = ui.previewCss("src/features/settings/view/panes/appearance.yss", "thumbnail_icon", @embedFile("appearance.yss"), .{ .width = 16, .height = 16, .flex_shrink = 0, .icon_color = ui.tokenRef(.color, "zw-fg-supporting"), });
/// 缩略图按 cover 缩放、居中（宽高与偏移随纹理尺寸算，`thumbnailImage`）。
pub fn thumbnailImage(texture: ?m.Texture, _: *const ui.ThemeTokens) ui.BoxStyle {
    const value = texture orelse return .{};
    const width: f32 = 72;
    const height: f32 = 48;
    const scale = @max(width / @as(f32, @floatFromInt(@max(value.width, 1))), height / @as(f32, @floatFromInt(@max(value.height, 1))));
    const image_width = @as(f32, @floatFromInt(value.width)) * scale;
    const image_height = @as(f32, @floatFromInt(value.height)) * scale;
    return .{ .position = .absolute, .width = .{ .px = image_width }, .height = .{ .px = image_height }, .inset = .{ .left = .{ .px = (width - image_width) / 2 }, .top = .{ .px = (height - image_height) / 2 } } };
}
pub const identity_copy = ui.previewCss("src/features/settings/view/panes/appearance.yss", "identity_copy", @embedFile("appearance.yss"), .{ .width = .fill, .flex = 1, .min_width = 0, .direction = .column, .gap = 2, .padding = .{ .top = 0, .right = 12, .bottom = 0, .left = 0 }, });
pub const file_name = ui.previewCss("src/features/settings/view/panes/appearance.yss", "file_name", @embedFile("appearance.yss"), .{ .font_size = 11.5, .font_weight = 500, .line_height = 18.0 / 11.5, .color = ui.tokenRef(.color, "fg-primary"), .wrap = .none, .text_overflow = .ellipsis, });
pub const file_name_box = ui.previewCss("src/features/settings/view/panes/appearance.yss", "file_name_box", @embedFile("appearance.yss"), .{ .width = .fill, .min_width = 0, });
pub const tip_fill = ui.previewCss("src/features/settings/view/panes/appearance.yss", "tip_fill", @embedFile("appearance.yss"), .{ .width = .fill, .min_width = 0, });
/// 行内材质预览（`settings.background.preview`）：高 116，圆角 8，上 10 下 5；宿主的材质图层铺满，标签浮在上面。
pub const material_preview = ui.previewCss("src/features/settings/view/panes/appearance.yss", "material_preview", @embedFile("appearance.yss"), .{ .width = .fill, .height = 116, .flex_shrink = 0, .position = .relative, .margin = .{ .top = 10, .right = 0, .bottom = 5, .left = 0 }, .corner_radius = 8, .overflow = .hidden, .background = ui.tokenRef(.color, "bg-primary"), });
pub const material_label = ui.previewCss("src/features/settings/view/panes/appearance.yss", "material_label", @embedFile("appearance.yss"), .{ .position = .absolute, .inset = ui.Inset{ .left = .{ .px = 11 }, .top = .{ .px = 9 } }, .padding = .{ .y = 0, .x = 4 }, .corner_radius = 4, .background = ui.tokenRef(.color, "zw-window-surface"), });
pub const material_code = ui.previewCss("src/features/settings/view/panes/appearance.yss", "material_code", @embedFile("appearance.yss"), .{ .position = .absolute, .inset = ui.Inset{ .left = .{ .px = 12 }, .bottom = .{ .px = 14 } }, .direction = .column, .padding = 4, .corner_radius = 5, .background = ui.tokenRef(.color, "zw-window-surface"), });
pub const material_code_line = ui.previewCss("src/features/settings/view/panes/appearance.yss", "material_code_line", @embedFile("appearance.yss"), .{ .font_size = 12, .line_height = 20.0 / 12.0, .color = ui.tokenRef(.color, "fg-primary"), .use_monospace_font = true, });
pub const material_action = ui.previewCss("src/features/settings/view/panes/appearance.yss", "material_action", @embedFile("appearance.yss"), .{ .position = .absolute, .inset = ui.Inset{ .right = .{ .px = 11 }, .top = .{ .px = 4 } }, });

// ── 字体与排版 / 预览 ──

/// 终端预览（`settings.font.preview`，`zCqTq`）：最小高 124，内边距 [10, 12]，间距 4；终端底色是数据（当前主题）。
pub fn previewSurface(text: m.PreviewText, t: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .min_height = 124, .direction = .column, .gap = 4, .padding = .{ .left = 12, .right = 12, .top = 10, .bottom = 10 }, .background = if (text.background) |bg| rgba(bg) else t.tokens.color.bg_secondary, .flex_shrink = 0 };
}
/// 预览正文卡片：没有内边距（终端面铺满，同旧 `previewSection` 的 `padding = ZERO`）。
pub const preview_body = ui.previewCss("src/features/settings/view/panes/appearance.yss", "preview_body", @embedFile("appearance.yss"), .{ .width = .fill, .direction = .column, .align_items = .stretch, .corner_radius = 12, .background = ui.tokenRef(.color, "zw-window-rest"), .overflow = .hidden, });
pub const preview_code = ui.previewCss("src/features/settings/view/panes/appearance.yss", "preview_code", @embedFile("appearance.yss"), .{ .width = .fill, .min_height = 48, .direction = .column, .flex_shrink = 0, });
pub const preview_fallback = ui.previewCss("src/features/settings/view/panes/appearance.yss", "preview_fallback", @embedFile("appearance.yss"), .{ .font_size = 11, .line_height = 17.0 / 11.0, .color = ui.tokenRef(.color, "warning"), .wrap = .word, });
pub const PreviewInk = struct { font_size: f32, font_weight: u16, font_family: u16, use_monospace_font: bool, line_height: f32, color: ui.Color };
fn ink(text: m.PreviewText, color: ui.Color) PreviewInk {
    return .{ .font_size = text.size, .font_weight = text.weight, .font_family = text.family, .use_monospace_font = text.family == 0, .line_height = text.line_height, .color = color };
}
/// 提示符（ANSI 2 绿）、命令（前景）、多语言行（前景 170 透明度）：草稿字号 / 字重 / 行高与解析出的字体。
pub fn previewPrompt(text: m.PreviewText, t: *const ui.ThemeTokens) PreviewInk {
    return ink(text, if (text.prompt) |c| rgba(c) else t.tokens.color.success);
}
pub fn previewCommand(text: m.PreviewText, t: *const ui.ThemeTokens) PreviewInk {
    return ink(text, if (text.foreground) |c| rgba(c) else t.tokens.color.fg_primary);
}
pub fn previewMultilingual(text: m.PreviewText, t: *const ui.ThemeTokens) PreviewInk {
    return ink(text, (if (text.foreground) |c| rgba(c) else t.tokens.color.fg_primary).withAlpha(170));
}
/// 命令行：行高 = 字号 × 行高倍率，光标紧跟命令（间距 2）。
pub fn previewCommandRow(text: m.PreviewText, _: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .height = .{ .px = text.size * text.line_height }, .direction = .row, .align_items = .center, .gap = 2 };
}
/// 光标：方块 = 一个单元格宽、一行高；竖线 2 宽；下划线 2 高、贴底。颜色强调色。
pub fn previewCaret(text: m.PreviewText, t: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .{ .px = text.caret_width }, .height = .{ .px = text.caret_height }, .background = t.tokens.color.accent, .flex_shrink = 0, .align_self = if (text.caret_low) .end else .center };
}
/// 光标闪烁：半周期 550ms（旧 `CursorBlink`）；视口外不推进。
pub fn caretBlink(phase: f32, _: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .opacity = if (phase < 0.5) 1 else 0 };
}
pub const caret_slot = ui.previewCss("src/features/settings/view/panes/appearance.yss", "caret_slot", @embedFile("appearance.yss"), .{ .direction = .row, .align_items = .center, .flex_shrink = 0, });

/// “字体与排版”子页的紧凑实时预览（`settings.font.live_preview`，Pencil `Ydlk6`，settings-copy）：
/// 行内边距 [10, 14, 14, 14]、间距 6；终端面圆角 8、内边距 [8, 12]、行间距 4，底色同上面的终端预览（当前主题）。
/// 文字与光标直接用上面的 `previewPrompt` / `previewCommand` / `previewCaret` / `previewMultilingual`（同一份草稿排版）。
pub const live_preview = ui.previewCss("src/features/settings/view/panes/appearance.yss", "live_preview", @embedFile("appearance.yss"), .{ .width = .fill, .direction = .column, .gap = 6, .padding = .{ .top = 10, .right = 14, .bottom = 14, .left = 14 }, .flex_shrink = 0, });
pub fn livePreviewSurface(text: m.PreviewText, t: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .direction = .column, .gap = 4, .padding = .{ .left = 12, .right = 12, .top = 8, .bottom = 8 }, .border = .{ .radius = 8 }, .background = if (text.background) |bg| rgba(bg) else t.tokens.color.bg_secondary, .flex_shrink = 0, .overflow = .hidden };
}

/// 工作区缩略预览（`settings.appearance.mini_preview`）：80 高，应用底色，圆角 9，内边距 8，间距 6。
pub fn miniRoot(p: m.MiniPreview, _: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 80 }, .background = rgba(p.tokens.app), .border = .{ .radius = 9 }, .direction = .column, .gap = 6, .padding = ui.Padding.all(8), .margin = .{ .top = 4, .bottom = 12 }, .flex_shrink = 0 };
}
pub const mini_top = ui.previewCss("src/features/settings/view/panes/appearance.yss", "mini_top", @embedFile("appearance.yss"), .{ .width = .fill, .height = 16, .direction = .row, .align_items = .center, .gap = 6, .flex_shrink = 0, });
pub const mini_body = ui.previewCss("src/features/settings/view/panes/appearance.yss", "mini_body", @embedFile("appearance.yss"), .{ .width = .fill, .height = 42, .direction = .row, .gap = 6, .flex_shrink = 0, });
pub fn miniLabel(p: m.MiniPreview, _: *const ui.ThemeTokens) struct { font_size: f32, line_height: f32, color: ui.Color } {
    return .{ .font_size = 10, .line_height = 1.4, .color = rgba(p.tokens.fg_2) };
}
pub fn miniIcon(p: m.MiniPreview, _: *const ui.ThemeTokens) ?ui.Color {
    return rgba(p.tokens.fg_2);
}
pub fn miniAccentIcon(p: m.MiniPreview, _: *const ui.ThemeTokens) ?ui.Color {
    return rgba(p.tokens.accent);
}
pub const mini_icon = ui.previewCss("src/features/settings/view/panes/appearance.yss", "mini_icon", @embedFile("appearance.yss"), .{ .width = 12, .height = 12, .flex_shrink = 0, });
pub const mini_server = ui.previewCss("src/features/settings/view/panes/appearance.yss", "mini_server", @embedFile("appearance.yss"), .{ .width = 14, .height = 14, .flex_shrink = 0, });
pub fn miniSidebar(p: m.MiniPreview, _: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .{ .px = 48 }, .height = .fill(), .padding = .{ .left = 8, .top = 7 }, .background = rgba(p.tokens.surface_1), .border = .{ .radius = 5 }, .flex_shrink = 0 };
}
pub fn miniTerminal(p: m.MiniPreview, _: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .fill(), .direction = .column, .background = rgba(p.terminal), .padding = ui.Padding.all(5.6), .border = .{ .radius = 5 } };
}
/// 终端里的一行（输入行相对高亮时第二行带选区底色）。
pub fn miniLine(_: m.MiniPreview, _: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 15.4 }, .direction = .row, .align_items = .center, .gap = 6, .flex_shrink = 0 };
}
pub fn miniInputLine(p: m.MiniPreview, _: *const ui.ThemeTokens) ui.BoxStyle {
    var s = miniLine(p, undefined);
    s.background = if (p.highlight) rgba(p.tokens.selection) else ui.Color.TRANSPARENT;
    return s;
}
pub fn miniStamp(p: m.MiniPreview, _: *const ui.ThemeTokens) struct { font_size: f32, line_height: f32, use_monospace_font: bool, color: ui.Color } {
    return .{ .font_size = 6.65, .line_height = 9.8 / 6.65, .use_monospace_font = true, .color = rgba(p.tokens.fg_3) };
}
pub fn miniRunning(p: m.MiniPreview, _: *const ui.ThemeTokens) struct { font_size: f32, line_height: f32, use_monospace_font: bool, color: ui.Color } {
    return .{ .font_size = 9.8, .line_height = 15.4 / 9.8, .use_monospace_font = true, .color = rgba(p.running) };
}
pub fn miniCommand(p: m.MiniPreview, _: *const ui.ThemeTokens) struct { font_size: f32, line_height: f32, use_monospace_font: bool, color: ui.Color } {
    return .{ .font_size = 9.8, .line_height = 15.4 / 9.8, .use_monospace_font = true, .color = rgba(p.foreground) };
}

//# yix-map appearance.yss
