// GENERATED FILE, do not edit: generated from overlays.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! KVM 卡片浮层的布局：只排位置、尺寸与层级；外观全部是原生组件默认（Tag / Button / TooltipSurface /
//! HintCapsule / Alert），唯一自画的是 O5 描边（accent token，2 px）。
const ui = @import("ui");

/// O1：工具栏状态区，跟在连接状态后面，宽度随内容；窄工具栏里可以收缩。
pub const status = ui.previewCss("src/plugins/bmc_ikvm/overlays.yss", "status", @embedFile("overlays.yss"), .{ .direction = .row, .align_items = .center, .gap = 6, .margin = .{ .top = 0, .right = 0, .bottom = 0, .left = 6 }, .flex_shrink = 1, .min_width = 0, .overflow = .hidden, });
/// O2：画面右上（宿主给出相对视频卡片的右 / 上边距），不参与命中。
pub const hud = ui.paramStyle(struct { right: f32, top: f32, pub const declared = &[_][]const u8{ "position", "inset", "z_index", "hit_behavior", }; pub fn resolve(args: @This(), t: *const ui.theme.Values) ui.BoxStyle { return ui.boxFrom(.{ .position = .absolute, .inset = ui.Inset{ .right = .{ .px = args.right }, .top = .{ .px = args.top } }, .z_index = 2, .hit_behavior = .pass_through, }, t); } });
/// O3：画面底边居中，左右各留出图标列后的区间，不参与命中。
pub const hint = ui.paramStyle(struct { left: f32, width: f32, bottom: f32, pub const declared = &[_][]const u8{ "position", "inset", "width", "direction", "justify", "z_index", "hit_behavior", }; pub fn resolve(args: @This(), t: *const ui.theme.Values) ui.BoxStyle { return ui.boxFrom(.{ .position = .absolute, .inset = ui.Inset{ .left = .{ .px = args.left }, .bottom = .{ .px = args.bottom } }, .width = args.width, .direction = .row, .justify = .center, .z_index = 2, .hit_behavior = .pass_through, }, t); } });
/// O4：画面正中（宿主按画面与图标算出左上角与宽度）。
pub const waiting = ui.paramStyle(struct { left: f32, top: f32, width: f32, pub const declared = &[_][]const u8{ "position", "inset", "width", "z_index", }; pub fn resolve(args: @This(), t: *const ui.theme.Values) ui.BoxStyle { return ui.boxFrom(.{ .position = .absolute, .inset = ui.Inset{ .left = .{ .px = args.left }, .top = .{ .px = args.top } }, .width = args.width, .z_index = 3, }, t); } });
/// O5：视频卡片 8 pt 黑边的内侧 2 px（inset 6），不盖远程像素、不参与命中。
pub const ai_frame = ui.paramStyle(struct { width: f32, height: f32, pub const declared = &[_][]const u8{ "position", "inset", "width", "height", "border_width", "border_color", "z_index", "hit_behavior", }; pub fn resolve(args: @This(), t: *const ui.theme.Values) ui.BoxStyle { return ui.boxFrom(.{ .position = .absolute, .inset = ui.Inset{ .left = .{ .px = 6 }, .top = .{ .px = 6 } }, .width = args.width, .height = args.height, .border_width = 2, .border_color = ui.tokenRef(.color, "accent"), .z_index = 1, .hit_behavior = .pass_through, }, t); } });

//# yix-map overlays.yss
