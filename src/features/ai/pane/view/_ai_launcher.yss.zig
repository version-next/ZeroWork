// GENERATED FILE, do not edit: generated from ai_launcher.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! 浮动 AI 图标的布局：只排位置与层级（不写颜色 / 圆角 / 阴影 / 尺寸以外的外观）。图标本身是原生 GlassButton 默认外观。
const ui = @import("ui");

/// 图标外框（48 × 48，GlassButton 纯图标默认尺寸）：相对窗口根绝对定位，坐标由宿主按 tab 内容区与停放的角算出。
/// 层级在卡片内容之上、浮动 AI 面板（200）与菜单之下（wqZ1s）。
pub const anchor = ui.paramStyle(struct { x: f32, y: f32, pub const declared = &[_][]const u8{ "position", "inset", "width", "height", "z_index", }; pub fn resolve(args: @This(), t: *const ui.theme.Values) ui.BoxStyle { return ui.boxFrom(.{ .position = .absolute, .inset = ui.Inset{ .left = .{ .px = args.x }, .top = .{ .px = args.y } }, .width = 48, .height = 48, .z_index = 199, }, t); } });
/// 角标：8 pt 圆点贴在圆形右上缘（tfmv1：x 36、y 4），不参与命中。
pub const dot = ui.previewCss("src/features/ai/pane/view/ai_launcher.yss", "dot", @embedFile("ai_launcher.yss"), .{ .position = .absolute, .inset = ui.Inset{ .left = .{ .px = 36 }, .top = .{ .px = 4 } }, .width = 8, .height = 8, .hit_behavior = .pass_through, });
/// 待审批脉冲：与角标重合的第二颗圆点（图标外框 + 36 / + 4），静止时透明；宿主的 ping 把它放大到 16 pt 并淡出。
pub const ring = ui.paramStyle(struct { x: f32, y: f32, pub const declared = &[_][]const u8{ "position", "inset", "width", "height", "opacity", "z_index", "hit_behavior", }; pub fn resolve(args: @This(), t: *const ui.theme.Values) ui.BoxStyle { return ui.boxFrom(.{ .position = .absolute, .inset = ui.Inset{ .left = .{ .px = args.x + 36 }, .top = .{ .px = args.y + 4 } }, .width = 8, .height = 8, .opacity = 0, .z_index = 199, .hit_behavior = .pass_through, }, t); } });
/// e2e 读取的状态名：零尺寸、裁掉、不参与命中。
pub const state = ui.previewCss("src/features/ai/pane/view/ai_launcher.yss", "state", @embedFile("ai_launcher.yss"), .{ .position = .absolute, .width = 0, .height = 0, .overflow = .hidden, .opacity = 0, .hit_behavior = .pass_through, });

//# yix-map ai_launcher.yss
