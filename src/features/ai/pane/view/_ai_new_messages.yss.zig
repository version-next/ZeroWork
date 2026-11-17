// GENERATED FILE, do not edit: generated from ai_new_messages.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! “新消息”提示的位置：叠在对话视口底部，离下缘（输入区上方）8，水平居中；整条不挡滚动与点击，只有按钮接收点击。
//! 按钮本身是原生 Button 默认外观。
const ui = @import("ui");

pub const holder = ui.previewCss("src/features/ai/pane/view/ai_new_messages.yss", "holder", @embedFile("ai_new_messages.yss"), .{ .position = .absolute, .inset = ui.Inset{ .left = .{ .px = 0 }, .right = .{ .px = 0 }, .bottom = .{ .px = 8 } }, .width = .fill, .height = .fit, .direction = .row, .justify = .center, .z_index = 10, .hit_behavior = .pass_through, });

//# yix-map ai_new_messages.yss
