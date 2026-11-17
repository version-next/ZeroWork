// GENERATED FILE, do not edit: generated from styles.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! ZeroWork settings window, Island B v3 settings revamp (Pencil `p6ZVS`
//! 外观与主题 overview, `z6LzX` and the other `›` subpages; components
//! `Bt1FV` Settings Nav, `uk2jl` Glass Nav, `L5zOX` Glass Icon Button,
//! `QGtx5` Pane Header, `EHLGD` Save Bar). Values are the design's numbers;
//! colors are zenit semantic tokens plus ZeroWork's zw-* island tokens.
const ui = @import("ui");

/// Window (`p6ZVS`): focus surface, padding [8, 0, 8, 8]; the floating
/// Settings Nav sits on the left, content fills the rest. (Legacy shell `settings_shell.card`.)
pub const shell = ui.previewCss("src/features/settings/view/styles.yss", "shell", @embedFile("styles.yss"), .{ .width = .fill, .height = .fill, .min_height = 0, .direction = .row, .gap = 0, .padding = .{ .top = 8, .right = 0, .bottom = 8, .left = 8 }, .background = ui.tokenRef(.color, "zw-window-surface"), .overflow = .hidden, });
/// `.yix` 设置窗口（`settings.panel`）：同 `shell`，但上内边距 0——内容列从窗口顶边开始，正文从浮动页头底下滚过
/// （znote 画板详情页：内容一直铺到窗口顶边）；导航浮层用自己的上外边距 8 保持原位置。
pub const panel = ui.previewCss("src/features/settings/view/styles.yss", "panel", @embedFile("styles.yss"), .{ .width = .fill, .height = .fill, .min_height = 0, .direction = .row, .gap = 0, .padding = .{ .top = 0, .right = 0, .bottom = 8, .left = 8 }, .background = ui.tokenRef(.color, "zw-window-surface"), .overflow = .hidden, });
/// Settings Nav (`Bt1FV`) 的原生玻璃容器 `W.GlassBox`（216 宽、圆角 14、内边距 [10, 8]、间距 12 是组件参数，见 nav.yix）：
/// 高度随父容器是组件参数 `fill={.height}`（G29）；根节点只补“不收缩”。材质、描边、投影全是 GlassBox 默认（人工验收反馈 1）。
/// 导航列：浮层上方 8 = 原窗口上内边距（内容列改为从窗口顶边开始后，导航浮层位置不变）。这 8 是窗口顶边，属于标题栏：
/// 一条窗口拖动区（`nav_window_inset`，`windowRegion={.drag}`，见 nav.yix），浮层在它下面占满剩余高度。
pub const nav_column = ui.previewCss("src/features/settings/view/styles.yss", "nav_column", @embedFile("styles.yss"), .{ .width = 216, .height = .fill, .min_height = 0, .flex_shrink = 0, .direction = .column, .align_items = .stretch, });
pub const nav_window_inset = ui.previewCss("src/features/settings/view/styles.yss", "nav_window_inset", @embedFile("styles.yss"), .{ .width = .fill, .height = 8, .flex_shrink = 0, });
pub const nav_glass = ui.previewCss("src/features/settings/view/styles.yss", "nav_glass", @embedFile("styles.yss"), .{ .flex = 1, .min_height = 0, });
/// 导航浮层顶部的窗口标题带：玻璃容器原来的 10 上内边距并进这里（位置不变），整条是窗口拖动区（`windowRegion={.drag}`，见 nav.yix）。
pub const nav_title_band = ui.previewCss("src/features/settings/view/styles.yss", "nav_title_band", @embedFile("styles.yss"), .{ .width = .fill, .flex_shrink = 0, .direction = .column, .align_items = .stretch, .padding = .{ .top = 10, .right = 0, .bottom = 0, .left = 0 }, });
/// Window top (`ZeTFX`): 28 high, padding [0, 6], gap 12.
pub const nav_top = ui.previewCss("src/features/settings/view/styles.yss", "nav_top", @embedFile("styles.yss"), .{ .width = .fill, .height = 28, .flex_shrink = 0, .direction = .row, .align_items = .center, .gap = ui.tokenRef(.space, "space300"), .padding = .{ .y = 0, .x = ui.tokenRef(.space, "space150") }, });
/// Categories (`h4aWe`): rows stacked with a 1pt gap.
pub const nav_list = ui.previewCss("src/features/settings/view/styles.yss", "nav_list", @embedFile("styles.yss"), .{ .width = .fill, .direction = .column, .align_items = .stretch, .gap = 1, });
/// Category row (`RI5FN` Project Row / normal): 28 high, padding [0, 8], gap 8, radius 6.
pub const nav_row = ui.previewCss("src/features/settings/view/styles.yss", "nav_row", @embedFile("styles.yss"), .{ .width = .fill, .height = 28, .flex_shrink = 0, .direction = .row, .align_items = .center, .justify = .start, .gap = ui.tokenRef(.space, "space200"), .padding = .{ .y = 0, .x = ui.tokenRef(.space, "space200") }, .corner_radius = 6, .background = ui.Color.TRANSPARENT, });
/// Category row, selected (`p6ZVS` › `VKdwK`): accent fill, white ink.
pub const nav_row_active = ui.previewCss("src/features/settings/view/styles.yss", "nav_row_active", @embedFile("styles.yss"), .{ .width = .fill, .height = 28, .flex_shrink = 0, .direction = .row, .align_items = .center, .justify = .start, .gap = ui.tokenRef(.space, "space200"), .padding = .{ .y = 0, .x = ui.tokenRef(.space, "space200") }, .corner_radius = 6, .background = ui.tokenRef(.color, "button-primary-bg"), .color = ui.tokenRef(.color, "button-primary-fg"), });
/// Local note (`wqeax`): 28 high, padding [0, 8], gap 6; lock 13 + 11pt text.
pub const nav_note = ui.previewCss("src/features/settings/view/styles.yss", "nav_note", @embedFile("styles.yss"), .{ .width = .fill, .height = 28, .flex_shrink = 0, .direction = .row, .align_items = .center, .gap = ui.tokenRef(.space, "space150"), .padding = .{ .y = 0, .x = ui.tokenRef(.space, "space200") }, });
/// Content (`ZFFi6`): fills the window beside the nav; no island.
pub const stage = ui.previewCss("src/features/settings/view/styles.yss", "stage", @embedFile("styles.yss"), .{ .width = .fill, .height = .fill, .min_width = 0, .min_height = 0, .direction = .column, .padding = 0, .background = ui.tokenRef(.color, "zw-window-surface"), });
pub const island = ui.previewCss("src/features/settings/view/styles.yss", "island", @embedFile("styles.yss"), .{ .width = .fill, .height = .fill, .min_width = 0, .min_height = 0, .direction = .column, .background = ui.tokenRef(.color, "zw-window-surface"), .overflow = .hidden, });

/// Page intro (`zCQxN`): padding [6, 14, 6, 12], gap 12 — Glass Nav,
/// heading, spacer, help.
pub const page_intro = ui.previewCss("src/features/settings/view/styles.yss", "page_intro", @embedFile("styles.yss"), .{ .width = .fill, .height = 48, .flex_shrink = 0, .direction = .row, .align_items = .center, .gap = ui.tokenRef(.space, "space300"), .padding = .{ .top = 6, .right = 14, .bottom = 6, .left = ui.tokenRef(.space, "space300") }, });
/// `.yix` 内容页（`settings.content`）：页头与标题栏边缘渐变绝对定位在列顶，所以列本身是定位上下文。
pub const page_frame = ui.previewCss("src/features/settings/view/styles.yss", "page_frame", @embedFile("styles.yss"), .{ .width = .fill, .height = .fill, .min_width = 0, .min_height = 0, .direction = .column, .position = .relative, });
/// `.yix` 页头（znote 画板详情页 header 行）：绝对定位在列顶、浮在视口与它的 scroll edge 之上；高 64、竖直中线 32（= 红绿灯
/// 中线），左右内边距 12、元素间距 12。拦截命中：滚到页头下的正文点不到（页头整条是标题栏拖动区，见 `header.yix`）。
pub const page_bar = ui.previewCss("src/features/settings/view/styles.yss", "page_bar", @embedFile("styles.yss"), .{ .position = .absolute, .inset = ui.Inset{ .top = .{ .px = 0 }, .left = .{ .px = 0 } }, .width = .fill, .height = 64, .direction = .row, .align_items = .center, .gap = ui.tokenRef(.space, "space300"), .padding = .{ .y = 0, .x = ui.tokenRef(.space, "space300") }, .hit_behavior = .self_and_children, });
/// `.yix` 视口内容：概览（`WswfJ`，[4, 24, 24, 24]）或面板（`CAEr8`，[8, 24, 76, 24]，76 让开浮动的 Save Bar）；
/// 视口从窗口顶边开始、页头浮在上面，所以上内边距再加页头高 64（静止时正文仍从页头下方开始）。
pub const PageBody = ui.previewCva("src/features/settings/view/styles.yss", "PageBody", @embedFile("styles.yss"), .{ .base = .{ .width = .fill, .direction = .column, .align_items = .stretch, .gap = 20, .padding = .{ .top = 72, .right = 24, .bottom = 76, .left = 24 }, }, .variants = .{ .overview = .{ .false = .{ }, .true = .{ .padding = .{ .top = 68, .right = 24, .bottom = 24, .left = 24 }, }, }, }, .defaults = .{ .overview = false, }, });
/// Page heading（znote header 的身份块）：上一级 › 标题一行，说明一行，行距 1。
pub const page_heading = ui.previewCss("src/features/settings/view/styles.yss", "page_heading", @embedFile("styles.yss"), .{ .min_width = 0, .flex_shrink = 1, .direction = .column, .align_items = .start, .gap = 1, });
/// 上一级 › 标题：间距 6，竖直居中。
pub const page_crumb_row = ui.previewCss("src/features/settings/view/styles.yss", "page_crumb_row", @embedFile("styles.yss"), .{ .min_width = 0, .direction = .row, .align_items = .center, .gap = 6, });
/// Panes (`CAEr8`): padding [8, 24, 76, 24], gap 20 (76 keeps the last pane clear of the floating Save Bar).
pub const panes = ui.previewCss("src/features/settings/view/styles.yss", "panes", @embedFile("styles.yss"), .{ .width = .fill, .direction = .column, .align_items = .stretch, .gap = 20, .padding = .{ .top = 8, .right = 24, .bottom = 76, .left = 24 }, });
/// Overview (`WswfJ`): padding [4, 24, 24, 24], gap 20.
pub const overview = ui.previewCss("src/features/settings/view/styles.yss", "overview", @embedFile("styles.yss"), .{ .width = .fill, .direction = .column, .align_items = .stretch, .gap = 20, .padding = .{ .top = 4, .right = 24, .bottom = 24, .left = 24 }, });
/// Hero (`HiaCV`): padding [8, 40, 4, 40], gap 8, centered.
pub const hero = ui.previewCss("src/features/settings/view/styles.yss", "hero", @embedFile("styles.yss"), .{ .width = .fill, .direction = .column, .align_items = .center, .gap = ui.tokenRef(.space, "space200"), .padding = .{ .top = 8, .right = 40, .bottom = 4, .left = 40 }, .flex_shrink = 0, });
/// Hero icon tile (`C6Mjq`): 56, radius 14, hairline.
pub const hero_tile = ui.previewCss("src/features/settings/view/styles.yss", "hero_tile", @embedFile("styles.yss"), .{ .width = 56, .height = 56, .flex_shrink = 0, .direction = .row, .align_items = .center, .justify = .center, .corner_radius = 14, .background = ui.tokenRef(.color, "zw-window-rest"), .border_overlay = true, .border_width = 1, .border_color = ui.tokenRef(.color, "border"), });
/// Overview list (`IhVlT`): radius 12, padding [0, 14].
pub const overview_list = ui.previewCss("src/features/settings/view/styles.yss", "overview_list", @embedFile("styles.yss"), .{ .width = .fill, .direction = .column, .align_items = .stretch, .padding = .{ .y = 0, .x = 14 }, .corner_radius = 12, .background = ui.tokenRef(.color, "zw-window-rest"), .flex_shrink = 0, });
/// Overview row (`sxDUF`): icon tile + inner, gap 12.
pub const overview_row = ui.previewCss("src/features/settings/view/styles.yss", "overview_row", @embedFile("styles.yss"), .{ .width = .fill, .direction = .row, .align_items = .center, .gap = ui.tokenRef(.space, "space300"), .padding = 0, .corner_radius = 0, .background = ui.Color.TRANSPARENT, .flex_shrink = 0, });
/// Overview row icon tile (`q1AKy`): 30, radius 8, hairline.
pub const overview_tile = ui.previewCss("src/features/settings/view/styles.yss", "overview_tile", @embedFile("styles.yss"), .{ .width = 30, .height = 30, .flex_shrink = 0, .direction = .row, .align_items = .center, .justify = .center, .corner_radius = 8, .background = ui.tokenRef(.color, "zw-window-surface"), .border_overlay = true, .border_width = 1, .border_color = ui.tokenRef(.color, "border"), });
/// Overview row inner (`asYm4`): padding [12, 0], gap 12, bottom hairline.
pub const overview_inner = ui.previewCss("src/features/settings/view/styles.yss", "overview_inner", @embedFile("styles.yss"), .{ .width = .fill, .flex = 1, .min_width = 0, .direction = .row, .align_items = .center, .gap = ui.tokenRef(.space, "space300"), .padding = .{ .y = 12, .x = 0 }, });
pub const overview_copy = ui.previewCss("src/features/settings/view/styles.yss", "overview_copy", @embedFile("styles.yss"), .{ .width = .fill, .flex = 1, .min_width = 0, .direction = .column, .align_items = .start, .gap = 2, });
pub const overview_summary_box = ui.previewCss("src/features/settings/view/styles.yss", "overview_summary_box", @embedFile("styles.yss"), .{ .width = .fill, .min_width = 0, .align_self = .stretch, });

/// Pane (`v8NDZM`): header above the body card, gap 6.
pub const pane = ui.previewCss("src/features/settings/view/styles.yss", "pane", @embedFile("styles.yss"), .{ .width = .fill, .direction = .column, .gap = ui.tokenRef(.space, "space150"), .padding = 0, .background = ui.Color.TRANSPARENT, .flex_shrink = 0, .min_width = 0, });
/// Pane Header (`QGtx5` as used by settings): 22 high, padding [0, 10], title then meta at the end.
pub const pane_header = ui.previewCss("src/features/settings/view/styles.yss", "pane_header", @embedFile("styles.yss"), .{ .width = .fill, .height = 22, .flex_shrink = 0, .direction = .row, .align_items = .center, .gap = ui.tokenRef(.space, "space150"), .padding = .{ .y = 0, .x = 10 }, .background = ui.Color.TRANSPARENT, });
/// Pane body card (`V4TNB`): radius 12, padding [0, 14], rest surface.
pub const pane_body = ui.previewCss("src/features/settings/view/styles.yss", "pane_body", @embedFile("styles.yss"), .{ .width = .fill, .direction = .column, .align_items = .stretch, .gap = 0, .padding = .{ .y = 0, .x = 14 }, .corner_radius = 12, .background = ui.tokenRef(.color, "zw-window-rest"), .overflow = .hidden, });
/// Setting row line (`ow4oe`): label column + control, gap 16, padding [10, 0].
pub const setting_line = ui.previewCss("src/features/settings/view/styles.yss", "setting_line", @embedFile("styles.yss"), .{ .width = .fill, .direction = .row, .align_items = .center, .gap = ui.tokenRef(.space, "space400"), .padding = .{ .y = 10, .x = 0 }, .min_width = 0, .flex_shrink = 0, });
/// Setting copy (`r3YXxg`): label over hint, gap 2.
pub const setting_copy = ui.previewCss("src/features/settings/view/styles.yss", "setting_copy", @embedFile("styles.yss"), .{ .width = .fill, .flex = 1, .min_width = 0, .direction = .column, .align_items = .start, .gap = 2, });

// ── 面板正文（P3 3e，`components/rows.yix`） ──

/// 一个分类的面板列（旧 `settings_styles.sectionColumn`）：面板之间 20。
pub const category_panes = ui.previewCss("src/features/settings/view/styles.yss", "category_panes", @embedFile("styles.yss"), .{ .width = .fill, .height = .fit, .direction = .column, .gap = 20, .flex_shrink = 0, .min_width = 0, });
/// 分类概览根（`WswfJ`）：hero 与子页面行之间 20。
pub const overview_root = ui.previewCss("src/features/settings/view/styles.yss", "overview_root", @embedFile("styles.yss"), .{ .width = .fill, .height = .fit, .direction = .column, .gap = 20, .flex_shrink = 0, .min_width = 0, });
/// 内容区里一个分类的外壳，本身不占间距。
pub const category_block = ui.previewCss("src/features/settings/view/styles.yss", "category_block", @embedFile("styles.yss"), .{ .width = .fill, .height = .fit, .direction = .column, .gap = 0, .flex_shrink = 0, .min_width = 0, });
/// 搜索结果（`settings.search.results`）：分类之间 20。
pub const search_results = ui.previewCss("src/features/settings/view/styles.yss", "search_results", @embedFile("styles.yss"), .{ .width = .fill, .height = .fit, .direction = .column, .gap = 20, .flex_shrink = 0, .min_width = 0, });
pub const empty_note = ui.previewCss("src/features/settings/view/styles.yss", "empty_note", @embedFile("styles.yss"), .{ .font_size = 11, .font_weight = 400, .line_height = 16.0 / 11.0, .color = ui.tokenRef(.color, "zw-fg-supporting"), });
/// Pane Header 文字（`QGtx5`）：标题 12 / 600，说明 11 次要墨色、单行省略。
pub const pane_title = ui.previewCss("src/features/settings/view/styles.yss", "pane_title", @embedFile("styles.yss"), .{ .font_size = 12, .font_weight = 600, .line_height = 16.0 / 12.0, .color = ui.tokenRef(.color, "fg-primary"), });
pub const pane_meta = ui.previewCss("src/features/settings/view/styles.yss", "pane_meta", @embedFile("styles.yss"), .{ .font_size = 11, .font_weight = 400, .line_height = 16.0 / 11.0, .color = ui.tokenRef(.color, "zw-fg-supporting"), .wrap = .none, .text_overflow = .ellipsis, });
pub const pane_meta_box = ui.previewCss("src/features/settings/view/styles.yss", "pane_meta_box", @embedFile("styles.yss"), .{ .min_width = 0, .flex_shrink = 1, });
/// 设置行根：行 + 校验提示；同一面板里相邻行之间一条发丝线（人工验收反馈 6，设计 `w3r3t`：1pt `border`，
/// 左右与行内容齐，即卡片内边距 14），最后一行下面没有。
pub const SettingRow = ui.previewCva("src/features/settings/view/styles.yss", "SettingRow", @embedFile("styles.yss"), .{ .base = .{ .width = .fill, .direction = .column, .gap = 0, .min_width = 0, .flex_shrink = 0, }, .variants = .{ .last = .{ .false = .{ .border_width = 0, .border_color = ui.tokenRef(.color, "border"), .border_bottom_width = 1, }, .true = .{ }, }, }, .defaults = .{ .last = false, }, });
/// 标签行：标签 + “?”，gap 4。
pub const setting_heading = ui.previewCss("src/features/settings/view/styles.yss", "setting_heading", @embedFile("styles.yss"), .{ .width = .fill, .min_width = 0, .direction = .row, .align_items = .center, .gap = 4, });
pub const setting_label = ui.previewCss("src/features/settings/view/styles.yss", "setting_label", @embedFile("styles.yss"), .{ .font_size = 13, .font_weight = 400, .line_height = 18.0 / 13.0, .color = ui.tokenRef(.color, "fg-primary"), });
pub const setting_hint = ui.previewCss("src/features/settings/view/styles.yss", "setting_hint", @embedFile("styles.yss"), .{ .font_size = 11.5, .font_weight = 400, .line_height = 1.4, .color = ui.tokenRef(.color, "zw-fg-supporting"), .wrap = .word, });
pub const setting_hint_box = ui.previewCss("src/features/settings/view/styles.yss", "setting_hint_box", @embedFile("styles.yss"), .{ .width = .fill, .min_width = 0, .max_width = 360, .align_self = .stretch, });
pub const setting_error = ui.previewCss("src/features/settings/view/styles.yss", "setting_error", @embedFile("styles.yss"), .{ .font_size = 11, .font_weight = 400, .line_height = 16.0 / 11.0, .color = ui.tokenRef(.color, "danger"), .padding = .{ .top = 0, .right = 0, .bottom = 8, .left = 0 }, });
pub const help_slot = ui.previewCss("src/features/settings/view/styles.yss", "help_slot", @embedFile("styles.yss"), .{ .flex_shrink = 0, .direction = .row, .align_items = .center, });
/// 只读 / 动作行的标签占满左侧。
pub const info_label_box = ui.previewCss("src/features/settings/view/styles.yss", "info_label_box", @embedFile("styles.yss"), .{ .width = .fill, .flex = 1, .min_width = 0, });
/// 只读值（旧 `settings_styles.value`）：右对齐，220 宽；路径单行省略。
pub const info_value_box = ui.previewCss("src/features/settings/view/styles.yss", "info_value_box", @embedFile("styles.yss"), .{ .width = 220, .flex_shrink = 0, .min_width = 0, .direction = .row, .justify = .end, });
pub const info_value = ui.previewCss("src/features/settings/view/styles.yss", "info_value", @embedFile("styles.yss"), .{ .font_size = 11.5, .font_weight = 400, .line_height = 17.0 / 11.5, .color = ui.tokenRef(.color, "zw-fg-supporting"), .text_align = .end, .wrap = .word, });
pub const info_path = ui.previewCss("src/features/settings/view/styles.yss", "info_path", @embedFile("styles.yss"), .{ .font_size = 11.5, .font_weight = 400, .line_height = 17.0 / 11.5, .color = ui.tokenRef(.color, "zw-fg-supporting"), .text_align = .end, .wrap = .none, .text_overflow = .ellipsis, });
/// 目录按钮：与原生 secondary / md 控件同尺寸的胶囊（180 × 32，圆角 6，1pt 描边），文件夹图标 + 单行省略的路径。
pub const DirectoryButton = ui.previewCva("src/features/settings/view/styles.yss", "DirectoryButton", @embedFile("styles.yss"), .{ .base = .{ .width = 180, .height = 32, .flex_shrink = 0, .min_width = 0, .direction = .row, .align_items = .center, .gap = ui.tokenRef(.space, "space150"), .padding = .{ .y = 0, .x = ui.tokenRef(.space, "space300") }, .corner_radius = 6, .background = ui.tokenRef(.color, "bg-primary"), .border_width = 1, .border_color = ui.tokenRef(.color, "border"), .color = ui.tokenRef(.color, "fg-primary"), .transition = ui.transition("background 150ms ease-out"), ._hover = .{ .background = ui.tokenRef(.color, "bg-hover"), }, ._active = .{ .background = ui.tokenRef(.color, "bg-active"), }, }, .variants = .{ .off = .{ .false = .{ }, .true = .{ .opacity = 0.5, ._hover = .{ .background = ui.tokenRef(.color, "bg-primary"), }, ._active = .{ .background = ui.tokenRef(.color, "bg-primary"), }, }, }, }, .defaults = .{ .off = false, }, });
pub const directory_icon = ui.previewCss("src/features/settings/view/styles.yss", "directory_icon", @embedFile("styles.yss"), .{ .width = 14, .height = 14, .flex_shrink = 0, .icon_color = ui.tokenRef(.color, "fg-primary"), });
pub const directory_label = ui.previewCss("src/features/settings/view/styles.yss", "directory_label", @embedFile("styles.yss"), .{ .font_size = 12, .font_weight = 400, .line_height = 1.5, .color = ui.tokenRef(.color, "fg-primary"), .wrap = .none, .text_overflow = .ellipsis, });
pub const directory_label_box = ui.previewCss("src/features/settings/view/styles.yss", "directory_label_box", @embedFile("styles.yss"), .{ .width = .fill, .flex = 1, .min_width = 0, });
/// 通知授权行：状态 + 说明“i”，等待中的提示。
pub const permission_status = ui.previewCss("src/features/settings/view/styles.yss", "permission_status", @embedFile("styles.yss"), .{ .min_width = 0, .direction = .row, .align_items = .center, .gap = 4, });
pub const permission_note = ui.previewCss("src/features/settings/view/styles.yss", "permission_note", @embedFile("styles.yss"), .{ .font_size = 11, .font_weight = 400, .line_height = 16.0 / 11.0, .color = ui.tokenRef(.color, "zw-fg-supporting"), });

/// Save Bar（`EHLGD`，H-save）：只定位——右 12、下 14 浮在视口上（在内容页里排在视口之后，画在它上面）。
/// 胶囊本身是原生 `W.GlassBox`（形状、内边距、间距是组件参数），材质、描边、投影全是 GlassBox 默认。
pub const save_bar_slot = ui.previewCss("src/features/settings/view/styles.yss", "save_bar_slot", @embedFile("styles.yss"), .{ .position = .absolute, .inset = ui.Inset{ .right = .{ .px = 12 }, .bottom = .{ .px = 14 } }, });
/// 胶囊正文：状态文字 + “撤销” + “保存”排成一行。
pub const save_bar_row = ui.previewCss("src/features/settings/view/styles.yss", "save_bar_row", @embedFile("styles.yss"), .{ .direction = .row, .align_items = .center, .gap = 8, });
/// “恢复默认…”行（H-save）：正文最后，右对齐。
pub const reset_row = ui.previewCss("src/features/settings/view/styles.yss", "reset_row", @embedFile("styles.yss"), .{ .width = .fill, .flex_shrink = 0, .direction = .row, .justify = .end, });
/// 确认对话框的挂载点：不占位（原生 Modal 自己挂到窗口浮层根上）。
pub const confirm_anchor = ui.previewCss("src/features/settings/view/styles.yss", "confirm_anchor", @embedFile("styles.yss"), .{ .position = .absolute, .width = 0, .height = 0, });
/// 确认对话框（原生 `W.Modal` 的正文；面板、遮罩、标题栏都是 Modal 默认）：说明、提示、按钮行。
pub const confirm_body = ui.previewCss("src/features/settings/view/styles.yss", "confirm_body", @embedFile("styles.yss"), .{ .width = .fill, .direction = .column, .gap = 8, });
pub const ConfirmMessage = ui.previewCva("src/features/settings/view/styles.yss", "ConfirmMessage", @embedFile("styles.yss"), .{ .base = .{ .font_size = 13, .font_weight = 400, .line_height = 1.5, .color = ui.tokenRef(.color, "fg-primary"), .wrap = .word, }, .variants = .{ .problem = .{ .false = .{ }, .true = .{ .color = ui.tokenRef(.color, "danger"), }, }, }, .defaults = .{ .problem = false, }, });
pub const confirm_notice = ui.previewCss("src/features/settings/view/styles.yss", "confirm_notice", @embedFile("styles.yss"), .{ .font_size = 12, .font_weight = 400, .line_height = 1.5, .color = ui.tokenRef(.color, "zw-fg-supporting"), .wrap = .word, });
pub const confirm_text_box = ui.previewCss("src/features/settings/view/styles.yss", "confirm_text_box", @embedFile("styles.yss"), .{ .width = .fill, });
pub const confirm_actions = ui.previewCss("src/features/settings/view/styles.yss", "confirm_actions", @embedFile("styles.yss"), .{ .width = .fill, .direction = .row, .align_items = .center, .gap = 8, .padding = .{ .top = 8, .right = 0, .bottom = 0, .left = 0 }, });

/// Keycap (`b9XxB`): 22 high, padding [0, 6], radius 5, hairline.
pub const keycap = ui.previewCss("src/features/settings/view/styles.yss", "keycap", @embedFile("styles.yss"), .{ .height = 22, .min_width = 22, .flex_shrink = 0, .direction = .row, .align_items = .center, .justify = .center, .padding = .{ .y = 0, .x = ui.tokenRef(.space, "space150") }, .corner_radius = 5, .background = ui.tokenRef(.color, "bg-primary"), .border_width = 1, .border_color = ui.tokenRef(.color, "border"), });

/// `.yix` 外壳（P3 3d）的样式。颜色全部是 token：不透明窗面是 `zw-window-surface`，次要文字是 `zw-fg-supporting`
/// （由 `app_theme.widgetTokensFrom` 按调色板发布）；浮层与浮动按钮是原生 `W.GlassBox`，不在这里画。
/// 原生窗口根（`settings.window`）。`min-height: 0`：不要 flex 的自动最小高度——否则材质 / 主题发布后重新测量，
/// 长内容页（外观与主题 › 主题）会把根撑到内容高度（1082.6），超出 780 的窗口，Save Bar 跑到窗外（bugfix-2 C）。
pub const window_root = ui.previewCss("src/features/settings/view/styles.yss", "window_root", @embedFile("styles.yss"), .{ .width = .fill, .height = .fill, .min_height = 0, .direction = .column, });
/// 红绿灯占位（`gq9c8`）：三个 12pt 圆点、间距 8。
pub const traffic_lights = ui.previewCss("src/features/settings/view/styles.yss", "traffic_lights", @embedFile("styles.yss"), .{ .width = 52, .height = 12, .flex_shrink = 0, });
pub const top_spacer = ui.previewCss("src/features/settings/view/styles.yss", "top_spacer", @embedFile("styles.yss"), .{ .width = .fill, .flex = 1, .height = 1, });
/// 搜索槽（`IKREe`）：宿主的搜索框填满 fill × 28。
pub const search_slot = ui.previewCss("src/features/settings/view/styles.yss", "search_slot", @embedFile("styles.yss"), .{ .width = .fill, .height = 28, .flex_shrink = 0, .direction = .row, .align_items = .stretch, });
/// 分类列表的滚动区（`settings.navigation.scroll`，S-5）：填满导航剩余高度；内容是 `nav_list`。
pub const nav_scroll = ui.previewCss("src/features/settings/view/styles.yss", "nav_scroll", @embedFile("styles.yss"), .{ .width = .fill, .height = .fill, .flex = 1, .min_height = 0, });
/// 内容视口（`settings.viewport`，S-5）：占满整列（从窗口顶边开始，正文从浮动页头底下滚过）；内容是 `PageBody`。原生回弹（反馈 5）。
/// 页头底下有滚动区：页头自己是窗口拖动区并拦截命中，滚到它底下的正文不会让空白处变成客户区（YIX_EXCEPTIONS S-10）。
pub const viewport = ui.previewCss("src/features/settings/view/styles.yss", "viewport", @embedFile("styles.yss"), .{ .flex = 1, .flex_shrink = 1, .min_height = 0, });
/// 搜索框（`IKREe`，S-4）：原生 `W.Input`（sm）填满槽，外观全用组件默认（人工验收反馈 1 / 原生规则：不再覆盖底色、描边与圆角）。
pub const search = ui.previewCss("src/features/settings/view/styles.yss", "search", @embedFile("styles.yss"), .{ .width = .fill, .height = 28, .min_width = 0, });
pub const note_icon = ui.previewCss("src/features/settings/view/styles.yss", "note_icon", @embedFile("styles.yss"), .{ .width = 13, .height = 13, .flex_shrink = 0, });
/// 岛内的内容列：内容页（`settings.content`）挂在这里。
pub const content_column = ui.previewCss("src/features/settings/view/styles.yss", "content_column", @embedFile("styles.yss"), .{ .width = .fill, .height = .fill, .min_width = 0, .min_height = 0, .direction = .column, });
pub const hero_icon = ui.previewCss("src/features/settings/view/styles.yss", "hero_icon", @embedFile("styles.yss"), .{ .width = 28, .height = 28, });
pub const hero_description_box = ui.previewCss("src/features/settings/view/styles.yss", "hero_description_box", @embedFile("styles.yss"), .{ .width = .fill, });
pub const footer_state_box = ui.previewCss("src/features/settings/view/styles.yss", "footer_state_box", @embedFile("styles.yss"), .{ .min_width = 0, .flex_shrink = 1, });

/// 外壳文字（颜色只引用 token；取值与原 `settings_shell` / `settings_styles` 的文字样式逐值相同）。
/// 窗口标题（`E8ZhR`，设计里禁用，只占位）：13 / 600。
pub const window_title = ui.previewCss("src/features/settings/view/styles.yss", "window_title", @embedFile("styles.yss"), .{ .font_size = 13, .font_weight = 600, .line_height = 18.0 / 13.0, .color = ui.tokenRef(.color, "fg-primary"), });
/// 本机说明（`EOp7g`）：11，次要墨色；锁（`NUODf`）13，淡墨。
pub const note_text = ui.previewCss("src/features/settings/view/styles.yss", "note_text", @embedFile("styles.yss"), .{ .font_size = 11, .font_weight = 400, .line_height = 14.0 / 11.0, .color = ui.tokenRef(.color, "fg-secondary"), });
pub const note_icon_ink = ui.previewCss("src/features/settings/view/styles.yss", "note_icon_ink", @embedFile("styles.yss"), .{ .icon_color = ui.tokenRef(.color, "zw-fg-faint"), });
/// 页头标题（znote header：名称 13 / 600 主墨色）、上一级（12.5 次要墨色）、›（11 次要墨色）、说明（10.5 次要墨色）；单行省略。
pub const page_title = ui.previewCss("src/features/settings/view/styles.yss", "page_title", @embedFile("styles.yss"), .{ .font_size = 13, .font_weight = 600, .line_height = 18.0 / 13.0, .color = ui.tokenRef(.color, "fg-primary"), .wrap = .none, .text_overflow = .ellipsis, });
pub const page_title_box = ui.previewCss("src/features/settings/view/styles.yss", "page_title_box", @embedFile("styles.yss"), .{ .min_width = 0, .flex_shrink = 1, });
pub const page_crumb = ui.previewCss("src/features/settings/view/styles.yss", "page_crumb", @embedFile("styles.yss"), .{ .font_size = 12.5, .font_weight = 400, .line_height = 17.0 / 12.5, .color = ui.tokenRef(.color, "zw-fg-supporting"), .wrap = .none, });
pub const page_crumb_box = ui.previewCss("src/features/settings/view/styles.yss", "page_crumb_box", @embedFile("styles.yss"), .{ .flex_shrink = 0, });
pub const page_crumb_chevron = ui.previewCss("src/features/settings/view/styles.yss", "page_crumb_chevron", @embedFile("styles.yss"), .{ .width = 11, .height = 11, .flex_shrink = 0, .icon_color = ui.tokenRef(.color, "zw-fg-supporting"), });
pub const page_subtitle = ui.previewCss("src/features/settings/view/styles.yss", "page_subtitle", @embedFile("styles.yss"), .{ .font_size = 10.5, .font_weight = 400, .line_height = 14.0 / 10.5, .color = ui.tokenRef(.color, "zw-fg-supporting"), .wrap = .none, .text_overflow = .ellipsis, });
pub const page_subtitle_box = ui.previewCss("src/features/settings/view/styles.yss", "page_subtitle_box", @embedFile("styles.yss"), .{ .min_width = 0, });
/// Hero 标题（`hObsG`）20 / 700；说明（`WGnxW`）12.5、行高 1.5、居中。
pub const hero_title = ui.previewCss("src/features/settings/view/styles.yss", "hero_title", @embedFile("styles.yss"), .{ .font_size = 20, .font_weight = 700, .line_height = 26.0 / 20.0, .color = ui.tokenRef(.color, "fg-primary"), });
pub const hero_text = ui.previewCss("src/features/settings/view/styles.yss", "hero_text", @embedFile("styles.yss"), .{ .font_size = 12.5, .font_weight = 400, .line_height = 1.5, .color = ui.tokenRef(.color, "zw-fg-supporting"), .text_align = .center, .wrap = .word, });
pub const hero_icon_ink = ui.previewCss("src/features/settings/view/styles.yss", "hero_icon_ink", @embedFile("styles.yss"), .{ .icon_color = ui.tokenRef(.color, "fg-secondary"), });
/// Save Bar 状态（`cJkdi`）：12，次要墨色，单行；校验无效 / 保存失败用危险墨色（H-save）。
pub const FooterStatus = ui.previewCva("src/features/settings/view/styles.yss", "FooterStatus", @embedFile("styles.yss"), .{ .base = .{ .font_size = 12, .font_weight = 400, .line_height = 16.0 / 12.0, .color = ui.tokenRef(.color, "zw-fg-supporting"), .wrap = .none, .text_overflow = .ellipsis, }, .variants = .{ .danger = .{ .false = .{ }, .true = .{ .color = ui.tokenRef(.color, "danger"), }, }, }, .defaults = .{ .danger = false, }, });

/// 导航行（`RI5FN` / `rQNox`）：`W.Pressable` 根上的外观，与原 ghost `W.Button` 逐状态相同——
/// 悬停 / 按下 bg-hover；选中是 action accent（悬停按下不变）；保存中（locked = 禁用）ghost 色调把底色清成透明；
/// 底色 150ms 过渡（ControlShell 的 fade）。
/// 原实现的两处“隐性”外观照搬（截图逐字节一致）：
/// - 前景色：ghost 色调把根的墨色（fg-primary；选中 button-primary-fg；禁用 fg-disabled）级联给追加进去的
///   文字，盖过了它们自己的 fg-secondary（文字总读继承色）——所以文字不写颜色、继承根；
/// - 左内边距 16：Button 空的 content 槽（宽 0）加一个 gap(8) 把内容右移 8，设计值是 8。
pub const NavRow = ui.previewCva("src/features/settings/view/styles.yss", "NavRow", @embedFile("styles.yss"), .{ .base = .{ .width = .fill, .height = 28, .flex_shrink = 0, .direction = .row, .align_items = .center, .justify = .start, .gap = ui.tokenRef(.space, "space200"), .padding = .{ .top = 0, .right = ui.tokenRef(.space, "space200"), .bottom = 0, .left = ui.tokenRef(.space, "space400") }, .corner_radius = 6, .background = ui.Color.TRANSPARENT, .color = ui.tokenRef(.color, "fg-primary"), .transition = ui.transition("background 150ms ease-out, border-color 150ms ease-out"), ._hover = .{ .background = ui.tokenRef(.color, "bg-hover"), }, ._active = .{ .background = ui.tokenRef(.color, "bg-hover"), }, }, .variants = .{ .selected = .{ .false = .{ }, .true = .{ .background = ui.tokenRef(.color, "button-primary-bg"), .color = ui.tokenRef(.color, "button-primary-fg"), ._hover = .{ .background = ui.tokenRef(.color, "button-primary-bg"), }, ._active = .{ .background = ui.tokenRef(.color, "button-primary-bg"), }, }, }, .locked = .{ .false = .{ }, .true = .{ .background = ui.Color.TRANSPARENT, .color = ui.tokenRef(.color, "fg-disabled"), ._hover = .{ .background = ui.Color.TRANSPARENT, }, ._active = .{ .background = ui.Color.TRANSPARENT, }, }, }, }, .defaults = .{ .selected = false, .locked = false, }, });
/// 分类图标（`oRKKl`）16，次要墨色；选中行上是主按钮前景色（图标的着色是显式的，不读继承色）。
pub const NavIcon = ui.previewCva("src/features/settings/view/styles.yss", "NavIcon", @embedFile("styles.yss"), .{ .base = .{ .width = 16, .height = 16, .flex_shrink = 0, .icon_color = ui.tokenRef(.color, "fg-secondary"), }, .variants = .{ .selected = .{ .false = .{ }, .true = .{ .icon_color = ui.tokenRef(.color, "button-primary-fg"), }, }, }, .defaults = .{ .selected = false, }, });
/// 分类名（`N86Dh`）13；选中行 500。颜色继承行根。
pub const NavLabel = ui.previewCva("src/features/settings/view/styles.yss", "NavLabel", @embedFile("styles.yss"), .{ .base = .{ .font_size = 13, .font_weight = 400, .line_height = 18.0 / 13.0, }, .variants = .{ .selected = .{ .false = .{ }, .true = .{ .font_weight = 500, }, }, }, .defaults = .{ .selected = false, }, });
pub const nav_label_box = ui.previewCss("src/features/settings/view/styles.yss", "nav_label_box", @embedFile("styles.yss"), .{ .width = .fill, .flex = 1, .min_width = 0, });

/// 概览行（`sxDUF`）：`W.Pressable` 根。悬停 / 按下只降不透明度（0.82 / 0.65），保存中不响应。
/// 同导航行：根墨色级联给文字（摘要设计里的次要墨色在原实现里没生效）；左内边距 12 = 空 content 槽 + gap(12)。
pub const OverviewRow = ui.previewCva("src/features/settings/view/styles.yss", "OverviewRow", @embedFile("styles.yss"), .{ .base = .{ .width = .fill, .height = .fit, .flex_shrink = 0, .direction = .row, .align_items = .center, .gap = ui.tokenRef(.space, "space300"), .padding = .{ .top = 0, .right = 0, .bottom = 0, .left = ui.tokenRef(.space, "space300") }, .corner_radius = 0, .background = ui.Color.TRANSPARENT, .color = ui.tokenRef(.color, "fg-primary"), .transition = ui.transition("background 150ms ease-out, border-color 150ms ease-out"), ._hover = .{ .opacity = 0.82, }, ._active = .{ .opacity = 0.65, }, }, .variants = .{ .locked = .{ .false = .{ }, .true = .{ .color = ui.tokenRef(.color, "fg-disabled"), ._hover = .{ .opacity = 1, }, ._active = .{ .opacity = 1, }, }, }, }, .defaults = .{ .locked = false, }, });
/// 行内（`asYm4`）：除最后一行外底部一条发丝线（bg-active，同面板行分隔线）。
pub const OverviewInner = ui.previewCva("src/features/settings/view/styles.yss", "OverviewInner", @embedFile("styles.yss"), .{ .base = .{ .width = .fill, .flex = 1, .min_width = 0, .direction = .row, .align_items = .center, .gap = ui.tokenRef(.space, "space300"), .padding = .{ .y = 12, .x = 0 }, }, .variants = .{ .last = .{ .false = .{ .border_width = 0, .border_color = ui.tokenRef(.color, "bg-active"), .border_bottom_width = 1, }, .true = .{ }, }, }, .defaults = .{ .last = false, }, });
/// 行图标：方块里的分类图标次要墨色，尾部箭头淡墨（显式着色，不随行根变）。
pub const overview_tile_icon = ui.previewCss("src/features/settings/view/styles.yss", "overview_tile_icon", @embedFile("styles.yss"), .{ .width = 16, .height = 16, .icon_color = ui.tokenRef(.color, "fg-secondary"), });
pub const overview_chevron = ui.previewCss("src/features/settings/view/styles.yss", "overview_chevron", @embedFile("styles.yss"), .{ .width = 16, .height = 16, .flex_shrink = 0, .icon_color = ui.tokenRef(.color, "zw-fg-faint"), });
/// 行标题（`u2A5RP`）13 / 400；摘要（`F6n7A`）11.5，单行省略。颜色继承行根。
pub const overview_label = ui.previewCss("src/features/settings/view/styles.yss", "overview_label", @embedFile("styles.yss"), .{ .font_size = 13, .font_weight = 400, .line_height = 18.0 / 13.0, });
pub const overview_summary = ui.previewCss("src/features/settings/view/styles.yss", "overview_summary", @embedFile("styles.yss"), .{ .font_size = 11.5, .font_weight = 400, .line_height = 16.0 / 11.5, .wrap = .none, .text_overflow = .ellipsis, });

/// 宿主状态行（岛底部，文字来自 `ViewModel.statusLine`）：10.5，次要墨色，不收缩。
pub const status_line = ui.previewCss("src/features/settings/view/styles.yss", "status_line", @embedFile("styles.yss"), .{ .font_size = 10.5, .color = ui.tokenRef(.color, "fg-secondary"), });
pub const status_line_box = ui.previewCss("src/features/settings/view/styles.yss", "status_line_box", @embedFile("styles.yss"), .{ .flex_shrink = 0, });

pub const info_path_box = ui.previewCss("src/features/settings/view/styles.yss", "info_path_box", @embedFile("styles.yss"), .{ .width = .fill, .min_width = 0, });

// ── 两级导航的列表行（F-set-plugins，`components/rows.yix` 的 `DrillRow`；设计 `T5k96` 的协议行） ──

/// 行根（`W.Pressable`）：图标底 + 行内，gap 12；悬停 / 按下只降不透明度（同概览行），保存中不响应。
pub const DrillRow = ui.previewCva("src/features/settings/view/styles.yss", "DrillRow", @embedFile("styles.yss"), .{ .base = .{ .width = .fill, .height = .fit, .flex_shrink = 0, .direction = .row, .align_items = .center, .gap = ui.tokenRef(.space, "space300"), .padding = 0, .background = ui.Color.TRANSPARENT, .color = ui.tokenRef(.color, "fg-primary"), ._hover = .{ .opacity = 0.82, }, ._active = .{ .opacity = 0.65, }, }, .variants = .{ .locked = .{ .false = .{ }, .true = .{ .color = ui.tokenRef(.color, "fg-disabled"), ._hover = .{ .opacity = 1, }, ._active = .{ .opacity = 1, }, }, }, }, .defaults = .{ .locked = false, }, });
/// 行内（`BsWmh`）：padding [9, 0]、gap 8；除最后一行外底部一条发丝线（bg-active，同概览行与面板行分隔线）。
pub const DrillInner = ui.previewCva("src/features/settings/view/styles.yss", "DrillInner", @embedFile("styles.yss"), .{ .base = .{ .width = .fill, .flex = 1, .min_width = 0, .direction = .row, .align_items = .center, .gap = ui.tokenRef(.space, "space200"), .padding = .{ .y = 9, .x = 0 }, }, .variants = .{ .last = .{ .false = .{ .border_width = 0, .border_color = ui.tokenRef(.color, "bg-active"), .border_bottom_width = 1, }, .true = .{ }, }, }, .defaults = .{ .last = false, }, });
/// 文案列（`EpTyH`）：标题 13 / 400 主墨色，摘要 11.5 次要墨色单行省略，gap 1。
pub const drill_copy = ui.previewCss("src/features/settings/view/styles.yss", "drill_copy", @embedFile("styles.yss"), .{ .width = .fill, .flex = 1, .min_width = 0, .direction = .column, .align_items = .start, .gap = 1, });
pub const DrillTitle = ui.previewCva("src/features/settings/view/styles.yss", "DrillTitle", @embedFile("styles.yss"), .{ .base = .{ .font_size = 13, .font_weight = 400, .line_height = 18.0 / 13.0, .color = ui.tokenRef(.color, "fg-primary"), .wrap = .none, .text_overflow = .ellipsis, }, .variants = .{ .muted = .{ .false = .{ }, .true = .{ .color = ui.tokenRef(.color, "fg-secondary"), }, }, }, .defaults = .{ .muted = false, }, });
/// 行图标：同 `overview_tile_icon`；被禁用的插件降为淡墨。
pub const DrillIcon = ui.previewCva("src/features/settings/view/styles.yss", "DrillIcon", @embedFile("styles.yss"), .{ .base = .{ .width = 16, .height = 16, .icon_color = ui.tokenRef(.color, "fg-secondary"), }, .variants = .{ .muted = .{ .false = .{ }, .true = .{ .icon_color = ui.tokenRef(.color, "zw-fg-faint"), }, }, }, .defaults = .{ .muted = false, }, });
pub const drill_summary = ui.previewCss("src/features/settings/view/styles.yss", "drill_summary", @embedFile("styles.yss"), .{ .font_size = 11.5, .font_weight = 400, .line_height = 16.0 / 11.5, .color = ui.tokenRef(.color, "zw-fg-supporting"), .wrap = .none, .text_overflow = .ellipsis, });
pub const drill_text_box = ui.previewCss("src/features/settings/view/styles.yss", "drill_text_box", @embedFile("styles.yss"), .{ .width = .fill, .min_width = 0, });
/// 尾注（`O4lQcV`）：11.5 次要墨色，不收缩。
pub const drill_trail = ui.previewCss("src/features/settings/view/styles.yss", "drill_trail", @embedFile("styles.yss"), .{ .font_size = 11.5, .font_weight = 400, .line_height = 16.0 / 11.5, .color = ui.tokenRef(.color, "zw-fg-supporting"), .wrap = .none, });
pub const drill_trail_box = ui.previewCss("src/features/settings/view/styles.yss", "drill_trail_box", @embedFile("styles.yss"), .{ .flex_shrink = 0, });

/// 选择行的原地编辑（S-13，`rows.CustomSelectRow`）：选择框与它下面不占位的 `W.Popover` 锚点排成一列
/// （锚点在选择框左下角，浮层默认 `bottom_start`、放不下时原生翻转）。
pub const custom_anchor = ui.previewCss("src/features/settings/view/styles.yss", "custom_anchor", @embedFile("styles.yss"), .{ .direction = .column, .align_items = .start, .flex_shrink = 0, });
/// 浮层正文（原生 `W.Popover` 的默认面板里）：说明 + 原生 `W.Input`。
pub const custom_editor = ui.previewCss("src/features/settings/view/styles.yss", "custom_editor", @embedFile("styles.yss"), .{ .width = .fill, .direction = .column, .gap = 8, .padding = 12, });

//# yix-map styles.yss
