// GENERATED FILE, do not edit: generated from editor_rows.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! 连接编辑器里可点的行：原生 `W.Pressable` 的 `look`，随主题由 zenit 按行自身状态（disabled / selected / expanded、
//! 悬停 / 按下）解析；颜色只用 token，不在挂载时取成定值。行内的文字与图标是视图自己的内容。
const ui = @import("ui");

/// 高级选项开关（hb6dT b7EPH）：整宽 15 高，标题 · 摘要 · 箭头紧排，透明底；外框行画顶部分隔线，开关本身没有悬停底色。
pub const advanced_toggle = ui.previewCss("src/plugins/remote/editor_rows.yss", "advanced_toggle", @embedFile("editor_rows.yss"), .{ .width = .fill, .height = 15, .flex_shrink = 0, .direction = .row, .align_items = .center, .justify = .start, .gap = 0, .padding = 0, .background = ui.Color.TRANSPARENT, });
/// 检测路线的节点卡片（Bridge 358:1328872 / 1328884）：146×76，内边距 10，纵向间距 3，圆角 9，岛面底色；
/// 被选为日志筛选条件时用选中底色。
pub const test_hop = ui.previewCss("src/plugins/remote/editor_rows.yss", "test_hop", @embedFile("editor_rows.yss"), .{ .width = 146, .height = 76, .flex_shrink = 0, .direction = .column, .gap = 3, .padding = 10, .corner_radius = 9, .background = ui.tokenRef(.color, "zw-island-rest"), ._selected = .{ .background = ui.tokenRef(.color, "selection-bg"), }, });
/// 核对页的“返回”行（zp7WE QgEGN）：整宽 37 高，右 4，间距 12，透明底；第一行以外顶部一条 bg-active 分隔线。
pub const back_row = ui.paramStyle(struct { first: bool, pub const declared = &[_][]const u8{ "width", "height", "padding", "gap", "background", "border_width", "corner_radius", "border_top_width", "border_top_color", }; pub fn resolve(args: @This(), t: *const ui.theme.Values) ui.BoxStyle { var out = ui.boxFrom(.{ .width = .fill, .height = 37, .padding = .{ .top = 0, .right = 4, .bottom = 0, .left = 0 }, .gap = 12, .background = ui.Color.TRANSPARENT, .border_width = 0, .corner_radius = 0, .border_top_width = 1, .border_top_color = ui.tokenRef(.color, "bg-active"), }, t); if (args.first) out = out.merge(ui.boxFrom(.{ .border_top_width = 0, }, t)); return out; } });
/// 检测卡片的标题行：整宽 18 高，间距 6，下方留 8。
pub const test_toggle = ui.previewCss("src/plugins/remote/editor_rows.yss", "test_toggle", @embedFile("editor_rows.yss"), .{ .width = .fill, .height = 18, .gap = 6, .margin = .{ .top = 0, .right = 0, .bottom = 8, .left = 0 }, });

//# yix-map editor_rows.yss
