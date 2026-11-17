// GENERATED FILE, do not edit: generated from float_fixture.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! 测试卡片内容排版（float-split）：只写布局。
const ui = @import("ui");

pub const root = ui.previewCss("src/features/workspace/view/float_fixture.yss", "root", @embedFile("float_fixture.yss"), .{ .width = .fill, .height = .fill, .min_width = 0, .min_height = 0, .direction = .column, .gap = 8, .padding = .{ .top = 8, .right = 12, .bottom = 12, .left = 12 }, });
pub const list = ui.previewCss("src/features/workspace/view/float_fixture.yss", "list", @embedFile("float_fixture.yss"), .{ .width = .fill, .height = .{ .grow = .{} }, .min_height = 0, });
pub const status = ui.previewCss("src/features/workspace/view/float_fixture.yss", "status", @embedFile("float_fixture.yss"), .{ .font_size = 12, .color = ui.tokenRef(.color, "fg-secondary"), .wrap = .none, .selectable = false, });

//# yix-map float_fixture.yss
