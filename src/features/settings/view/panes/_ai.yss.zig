// GENERATED FILE, do not edit: generated from ai.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! “AI 辅助”面板正文（F-set-ai，人工验收反馈第 10 条后半）的样式：服务提供方列表行（`GV8pb` › `lxZqv`）、
//! 提供方详情、模型行、模型编辑器与删除确认的正文布局、技能与 MCP 的条目。
//! 控件全是原生组件（Button / Input / Select / Switch / Checkbox / Tag / Badge / Tooltip / Menu / Modal / Textarea），
//! 这里只给布局盒子与 `W.Pressable` 根（它没有自己的外观）定外观；颜色全是 token。
const ui = @import("ui");

/// 提供方列表行（`bCylr`）：`W.Pressable` 根，头像 + 行内，gap 12。悬停 / 按下只降不透明度（同概览行），保存中不响应。
pub const AiProviderRow = ui.previewCva("src/features/settings/view/panes/ai.yss", "AiProviderRow", @embedFile("ai.yss"), .{ .base = .{ .width = .fill, .height = .fit, .flex_shrink = 0, .direction = .row, .align_items = .center, .gap = 12, .padding = 0, .corner_radius = 0, .background = ui.Color.TRANSPARENT, .color = ui.tokenRef(.color, "fg-primary"), ._hover = .{ .opacity = 0.82, }, ._active = .{ .opacity = 0.65, }, }, .variants = .{ .locked = .{ .false = .{ }, .true = .{ .color = ui.tokenRef(.color, "fg-disabled"), ._hover = .{ .opacity = 1, }, ._active = .{ .opacity = 1, }, }, }, }, .defaults = .{ .locked = false, }, });
/// 行内（`FtJpK`）：padding [9, 0]，gap 8；除最后一行外底部一条发丝线（同设置行分隔线，人工验收反馈 6）。
pub const AiProviderInner = ui.previewCva("src/features/settings/view/panes/ai.yss", "AiProviderInner", @embedFile("ai.yss"), .{ .base = .{ .width = .fill, .flex = 1, .min_width = 0, .direction = .row, .align_items = .center, .gap = 8, .padding = .{ .y = 9, .x = 0 }, }, .variants = .{ .last = .{ .false = .{ .border_width = 0, .border_color = ui.tokenRef(.color, "border"), .border_bottom_width = 1, }, .true = .{ }, }, }, .defaults = .{ .last = false, }, });
/// 头像（`W:y0dYR` 的位置；zenit 没有 Avatar 组件，缺口 G46）：28 圆、文字 11 / 600。
pub const ai_avatar = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_avatar", @embedFile("ai.yss"), .{ .width = 28, .height = 28, .flex_shrink = 0, .direction = .row, .align_items = .center, .justify = .center, .corner_radius = 14, .background = ui.tokenRef(.color, "bg-active"), });
pub const ai_avatar_text = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_avatar_text", @embedFile("ai.yss"), .{ .font_size = 11, .font_weight = 600, .line_height = 14.0 / 11.0, .color = ui.tokenRef(.color, "fg-secondary"), });
/// 名称 13 / 400、摘要 11.5 次要墨色（`l2nChT` / `S4NvBu`），单行省略。
pub const ai_copy = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_copy", @embedFile("ai.yss"), .{ .width = .fill, .flex = 1, .min_width = 0, .direction = .column, .align_items = .start, .gap = 1, });
pub const ai_row_title = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_row_title", @embedFile("ai.yss"), .{ .font_size = 13, .font_weight = 400, .line_height = 18.0 / 13.0, .wrap = .none, .text_overflow = .ellipsis, });
pub const ai_row_summary = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_row_summary", @embedFile("ai.yss"), .{ .font_size = 11.5, .font_weight = 400, .line_height = 16.0 / 11.5, .color = ui.tokenRef(.color, "zw-fg-supporting"), .wrap = .none, .text_overflow = .ellipsis, });
pub const ai_row_title_box = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_row_title_box", @embedFile("ai.yss"), .{ .width = .fill, .min_width = 0, });
/// 状态文字（`qOqrZ`“未启用”）。
pub const ai_row_state = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_row_state", @embedFile("ai.yss"), .{ .font_size = 11.5, .font_weight = 400, .line_height = 16.0 / 11.5, .color = ui.tokenRef(.color, "zw-fg-supporting"), .wrap = .none, });
pub const ai_chevron = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_chevron", @embedFile("ai.yss"), .{ .width = 16, .height = 16, .flex_shrink = 0, .icon_color = ui.tokenRef(.color, "zw-fg-faint"), });
/// 列表下的动作行（`N3X9H`）：右对齐，上 2。
pub const ai_actions = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_actions", @embedFile("ai.yss"), .{ .width = .fill, .flex_shrink = 0, .direction = .row, .justify = .end, .align_items = .center, .gap = 8, .padding = .{ .top = 2, .right = 0, .bottom = 0, .left = 0 }, });
/// 列表为空：图标、标题、说明、按钮，居中。
/// 提供方级提示（`settings.ai.provider_error`）。
pub const ai_error = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_error", @embedFile("ai.yss"), .{ .font_size = 11.5, .font_weight = 400, .line_height = 16.0 / 11.5, .color = ui.tokenRef(.color, "danger"), .wrap = .word, });
pub const ai_error_box = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_error_box", @embedFile("ai.yss"), .{ .width = .fill, });

/// 详情页：输入框的列（输入框 + 显示 / 隐藏 API Key）。
pub const ai_control = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_control", @embedFile("ai.yss"), .{ .flex_shrink = 0, .direction = .row, .align_items = .center, .gap = 4, });
/// 面板页头右侧的动作（获取模型清单 / 添加模型）。
pub const ai_header_actions = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_header_actions", @embedFile("ai.yss"), .{ .flex_shrink = 0, .direction = .row, .align_items = .center, .gap = 4, });
/// 模型清单状态（获取中 / 已获取 / 失败）：卡片内第一行。
pub const ai_note = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_note", @embedFile("ai.yss"), .{ .font_size = 11.5, .font_weight = 400, .line_height = 16.0 / 11.5, .color = ui.tokenRef(.color, "zw-fg-supporting"), .wrap = .word, });
pub const ai_note_box = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_note_box", @embedFile("ai.yss"), .{ .width = .fill, .padding = .{ .top = 10, .right = 0, .bottom = 0, .left = 0 }, });
/// 模型行（`ZN8NK`）：名称、上下文、能力标签、默认徽标，右侧星标 / 编辑 / 删除。
pub const ai_model_name = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_model_name", @embedFile("ai.yss"), .{ .min_width = 0, .flex_shrink = 1, .direction = .row, .align_items = .center, });
pub const ai_model_text = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_model_text", @embedFile("ai.yss"), .{ .font_size = 12.5, .font_weight = 400, .line_height = 18.0 / 12.5, .color = ui.tokenRef(.color, "fg-primary"), .wrap = .none, .text_overflow = .ellipsis, });
pub const ai_model_meta = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_model_meta", @embedFile("ai.yss"), .{ .flex_shrink = 0, .direction = .row, .align_items = .center, .gap = 6, });
pub const ai_model_context = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_model_context", @embedFile("ai.yss"), .{ .font_size = 11, .font_weight = 400, .line_height = 16.0 / 11.0, .color = ui.tokenRef(.color, "zw-fg-supporting"), .wrap = .none, });
pub const ai_model_actions = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_model_actions", @embedFile("ai.yss"), .{ .flex_shrink = 0, .direction = .row, .align_items = .center, .gap = 2, });
/// 模型名的 `W.Pressable` 根（点开编辑器）：只给最小外观，悬停降不透明度。
pub const AiModelName = ui.previewCva("src/features/settings/view/panes/ai.yss", "AiModelName", @embedFile("ai.yss"), .{ .base = .{ .min_width = 0, .flex_shrink = 1, .direction = .row, .align_items = .center, .corner_radius = 4, .background = ui.Color.TRANSPARENT, ._hover = .{ .opacity = 0.75, }, ._active = .{ .opacity = 0.6, }, }, });
/// 没有模型时的空态行。
pub const ai_label = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_label", @embedFile("ai.yss"), .{ .font_size = 13, .font_weight = 400, .line_height = 18.0 / 13.0, .color = ui.tokenRef(.color, "fg-primary"), });
pub const ai_hint = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_hint", @embedFile("ai.yss"), .{ .font_size = 11.5, .font_weight = 400, .line_height = 1.4, .color = ui.tokenRef(.color, "zw-fg-supporting"), .wrap = .word, });
/// 详情页底部的删除 / 取消新增：右对齐。
pub const ai_danger_row = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_danger_row", @embedFile("ai.yss"), .{ .width = .fill, .flex_shrink = 0, .direction = .row, .justify = .end, .align_items = .center, });

/// 模型编辑器 / 删除确认（原生 `W.Modal` 的正文；面板、遮罩、标题栏都是 Modal 默认）。
pub const ai_dialog = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_dialog", @embedFile("ai.yss"), .{ .width = .fill, .direction = .column, .gap = 14, });
/// 模型编辑器的表单区：原生 `W.ScrollArea`，高度随内容、最多 280（原生 `W.Modal` 的高度上限在挂载时固定、正文不滚动——
/// 缺口 G40；表单放进滚动区，紧凑窗口（高 480）里页脚按钮仍在窗口内）。
pub const ai_dialog_scroll = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_dialog_scroll", @embedFile("ai.yss"), .{ .width = .fill, .height = .{ .fit = .{ .max = 280 } }, .flex_shrink = 1, .min_height = 0, });
pub const ai_dialog_scroll_body = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_dialog_scroll_body", @embedFile("ai.yss"), .{ .width = .fill, .direction = .column, .gap = 14, .padding = .{ .top = 0, .right = 4, .bottom = 0, .left = 0 }, });
pub const ai_dialog_sub = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_dialog_sub", @embedFile("ai.yss"), .{ .font_size = 12, .font_weight = 400, .line_height = 1.5, .color = ui.tokenRef(.color, "zw-fg-supporting"), });
pub const ai_field = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_field", @embedFile("ai.yss"), .{ .width = .fill, .direction = .column, .gap = 6, });
pub const ai_field_heading = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_field_heading", @embedFile("ai.yss"), .{ .width = .fill, .direction = .row, .align_items = .center, .gap = 6, });
pub const ai_field_label = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_field_label", @embedFile("ai.yss"), .{ .font_size = 12.5, .font_weight = 500, .line_height = 18.0 / 12.5, .color = ui.tokenRef(.color, "fg-primary"), });
pub const ai_catalog_row = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_catalog_row", @embedFile("ai.yss"), .{ .width = .fill, .direction = .row, .align_items = .center, .gap = 8, });
pub const ai_catalog_status = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_catalog_status", @embedFile("ai.yss"), .{ .font_size = 11.5, .font_weight = 400, .line_height = 16.0 / 11.5, .color = ui.tokenRef(.color, "zw-fg-supporting"), .wrap = .word, });
pub const ai_catalog_status_box = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_catalog_status_box", @embedFile("ai.yss"), .{ .width = .fill, .flex = 1, .min_width = 0, });
pub const ai_capability = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_capability", @embedFile("ai.yss"), .{ .width = .fill, .direction = .row, .align_items = .center, .gap = 8, });
pub const ai_capability_label = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_capability_label", @embedFile("ai.yss"), .{ .width = .fill, .flex = 1, .min_width = 0, .direction = .row, .align_items = .center, .gap = 6, });
/// 能力来源的小图标（接口已返回 / 手动设置 / 未返回）：原生 Tooltip 说明。
pub const AiSource = ui.previewCva("src/features/settings/view/panes/ai.yss", "AiSource", @embedFile("ai.yss"), .{ .base = .{ .width = 14, .height = 14, .flex_shrink = 0, .icon_color = ui.tokenRef(.color, "fg-secondary"), }, .variants = .{ .tone = .{ .manual = .{ .icon_color = ui.tokenRef(.color, "fg-secondary"), }, .api = .{ .icon_color = ui.tokenRef(.color, "success"), }, .missing = .{ .icon_color = ui.tokenRef(.color, "warning"), }, }, }, .defaults = .{ .tone = .manual, }, });
pub const ai_source_slot = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_source_slot", @embedFile("ai.yss"), .{ .width = 18, .height = 18, .flex_shrink = 0, .direction = .row, .align_items = .center, .justify = .center, });
pub const ai_efforts = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_efforts", @embedFile("ai.yss"), .{ .width = .fill, .direction = .column, .gap = 6, .padding = .{ .top = 0, .right = 0, .bottom = 0, .left = 2 }, });
pub const ai_efforts_grid = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_efforts_grid", @embedFile("ai.yss"), .{ .width = .fill, .direction = .row, .flex_wrap = .wrap, .gap = 10, });
pub const ai_test_row = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_test_row", @embedFile("ai.yss"), .{ .width = .fill, .direction = .row, .align_items = .center, .gap = 12, .padding = .{ .y = 10, .x = 12 }, .corner_radius = 8, .background = ui.tokenRef(.color, "bg-secondary"), });
pub const ai_test_status = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_test_status", @embedFile("ai.yss"), .{ .font_size = 12, .font_weight = 400, .line_height = 1.5, .color = ui.tokenRef(.color, "fg-primary"), .wrap = .word, });
pub const ai_test_status_box = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_test_status_box", @embedFile("ai.yss"), .{ .width = .fill, .flex = 1, .min_width = 0, });
pub const ai_dialog_error = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_dialog_error", @embedFile("ai.yss"), .{ .font_size = 11.5, .font_weight = 400, .line_height = 16.0 / 11.5, .color = ui.tokenRef(.color, "danger"), .wrap = .word, });
pub const ai_dialog_actions = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_dialog_actions", @embedFile("ai.yss"), .{ .width = .fill, .direction = .row, .align_items = .center, .justify = .end, .gap = 8, .padding = .{ .top = 4, .right = 0, .bottom = 0, .left = 0 }, });
pub const ai_dialog_message = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_dialog_message", @embedFile("ai.yss"), .{ .font_size = 13, .font_weight = 400, .line_height = 1.5, .color = ui.tokenRef(.color, "fg-primary"), .wrap = .word, });
pub const ai_dialog_text_box = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_dialog_text_box", @embedFile("ai.yss"), .{ .width = .fill, });
pub const ai_dialog_anchor = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_dialog_anchor", @embedFile("ai.yss"), .{ .position = .absolute, .width = 0, .height = 0, });

/// 技能 / MCP 条目（旧 `settings_mcp_styles.service` 的布局）：一行身份 + 开关 + 动作，下面可展开详情。
pub const ai_ext_toolbar = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_ext_toolbar", @embedFile("ai.yss"), .{ .width = .fill, .flex_shrink = 0, .direction = .row, .align_items = .center, .gap = 12, .padding = .{ .y = 10, .x = 0 }, });
pub const ai_ext_summary = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_ext_summary", @embedFile("ai.yss"), .{ .font_size = 11.5, .font_weight = 400, .line_height = 16.0 / 11.5, .color = ui.tokenRef(.color, "zw-fg-supporting"), .wrap = .none, });
pub const ai_ext_summary_box = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_ext_summary_box", @embedFile("ai.yss"), .{ .width = .fill, .flex = 1, .min_width = 0, });
pub const AiExtRow = ui.previewCva("src/features/settings/view/panes/ai.yss", "AiExtRow", @embedFile("ai.yss"), .{ .base = .{ .width = .fill, .flex_shrink = 0, .direction = .column, .gap = 6, .padding = .{ .y = 10, .x = 0 }, .min_width = 0, }, .variants = .{ .last = .{ .false = .{ .border_width = 0, .border_color = ui.tokenRef(.color, "border"), .border_bottom_width = 1, }, .true = .{ }, }, }, .defaults = .{ .last = false, }, });
pub const ai_ext_line = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_ext_line", @embedFile("ai.yss"), .{ .width = .fill, .direction = .row, .align_items = .center, .gap = 10, .min_width = 0, });
pub const ai_ext_icon_tile = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_ext_icon_tile", @embedFile("ai.yss"), .{ .width = 28, .height = 28, .flex_shrink = 0, .direction = .row, .align_items = .center, .justify = .center, .corner_radius = 14, .background = ui.tokenRef(.color, "bg-active"), });
pub const ai_ext_icon = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_ext_icon", @embedFile("ai.yss"), .{ .width = 16, .height = 16, .icon_color = ui.tokenRef(.color, "fg-secondary"), });
pub const ai_ext_identity = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_ext_identity", @embedFile("ai.yss"), .{ .width = .fill, .flex = 1, .min_width = 0, .direction = .column, .gap = 3, });
pub const ai_ext_title = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_ext_title", @embedFile("ai.yss"), .{ .font_size = 12.5, .font_weight = 600, .line_height = 18.0 / 12.5, .color = ui.tokenRef(.color, "fg-primary"), .wrap = .none, .text_overflow = .ellipsis, });
pub const ai_ext_meta = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_ext_meta", @embedFile("ai.yss"), .{ .font_size = 11, .font_weight = 400, .line_height = 16.0 / 11.0, .color = ui.tokenRef(.color, "zw-fg-supporting"), .wrap = .none, .text_overflow = .ellipsis, });
pub const ai_ext_text_box = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_ext_text_box", @embedFile("ai.yss"), .{ .width = .fill, .min_width = 0, });
pub const ai_ext_failure = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_ext_failure", @embedFile("ai.yss"), .{ .font_size = 11.5, .font_weight = 400, .line_height = 16.0 / 11.5, .color = ui.tokenRef(.color, "danger"), .wrap = .word, });
pub const ai_ext_failure_box = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_ext_failure_box", @embedFile("ai.yss"), .{ .width = .fill, .min_width = 0, .padding = .{ .top = 0, .right = 0, .bottom = 0, .left = 38 }, });
pub const ai_ext_form = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_ext_form", @embedFile("ai.yss"), .{ .width = .fill, .direction = .column, .gap = 10, .padding = .{ .y = 10, .x = 0 }, });
pub const ai_ext_buttons = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_ext_buttons", @embedFile("ai.yss"), .{ .width = .fill, .direction = .row, .align_items = .center, .gap = 6, });
pub const ai_ext_job = ui.previewCss("src/features/settings/view/panes/ai.yss", "ai_ext_job", @embedFile("ai.yss"), .{ .width = .fill, .direction = .row, .align_items = .center, .gap = 8, });

//# yix-map ai.yss
