// GENERATED FILE, do not edit: generated from ai_panel_motion.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! AI 面板过渡探针的布局：相对窗口根绝对定位、全透明、不参与命中，不画任何外观。
const ui = @import("ui");

/// 过渡本帧的快照矩形（窗口坐标），全透明且不参与命中。
pub const frame = ui.paramStyle(struct { x: f32, y: f32, w: f32, h: f32, pub const declared = &[_][]const u8{ "position", "inset", "width", "height", "opacity", "hit_behavior", }; pub fn resolve(args: @This(), t: *const ui.theme.Values) ui.BoxStyle { return ui.boxFrom(.{ .position = .absolute, .inset = ui.Inset{ .left = .{ .px = args.x }, .top = .{ .px = args.y } }, .width = args.w, .height = args.h, .opacity = 0, .hit_behavior = .pass_through, }, t); } });
/// 阶段名与锚点名：零尺寸、裁掉。
pub const label = ui.previewCss("src/features/ai/pane/view/ai_panel_motion.yss", "label", @embedFile("ai_panel_motion.yss"), .{ .position = .absolute, .width = 0, .height = 0, .overflow = .hidden, .opacity = 0, .hit_behavior = .pass_through, });

//# yix-map ai_panel_motion.yss
