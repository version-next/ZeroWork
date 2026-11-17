// GENERATED FILE, do not edit: generated from ai_composer.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! AI composer area layout (Pencil Kaf7E ③ / ⑤; view: ai_composer.yix). The field, the controls
//! and the decision panel are native; these styles only place them.
const ui = @import("ui");

/// The area: queue, decision panel and field 8 apart; margins by width (⑤, decided by the host);
/// pinned to its content height once measured (0 = fit).
pub const area = ui.paramStyle(struct { pad: ui.Padding, h: f32, pub const declared = &[_][]const u8{ "position", "width", "height", "flex_shrink", "direction", "gap", "padding", }; pub fn resolve(args: @This(), t: *const ui.theme.Values) ui.BoxStyle { return ui.boxFrom(.{ .position = .relative, .width = .fill, .height = if (args.h > 0) ui.Sizing{ .px = args.h } else ui.Sizing{ .fit = .{} }, .flex_shrink = 0, .direction = .column, .gap = 8, .padding = args.pad, }, t); } });
/// A slot the host fills (the request queue view).
pub const slot = ui.previewCss("src/features/ai/composer/view/ai_composer.yss", "slot", @embedFile("ai_composer.yss"), .{ .width = .fill, .height = .fit, .direction = .column, .flex_shrink = 0, });
/// The header row's chip slot (attachment views).
pub const chips = ui.previewCss("src/features/ai/composer/view/ai_composer.yss", "chips", @embedFile("ai_composer.yss"), .{ .width = .fill, .height = .fit, .direction = .column, });
/// Send / Stop side by side at the end of the tool row.
pub const actions = ui.previewCss("src/features/ai/composer/view/ai_composer.yss", "actions", @embedFile("ai_composer.yss"), .{ .width = .fit, .height = .fit, .direction = .row, .align_items = .center, .gap = 4, .flex_shrink = 0, });
/// “稍后处理” capsule: right above the composer area, aligned to its right margin.
pub const capsule = ui.paramStyle(struct { side: f32, pub const declared = &[_][]const u8{ "position", "inset", "margin", "z_index", }; pub fn resolve(args: @This(), t: *const ui.theme.Values) ui.BoxStyle { return ui.boxFrom(.{ .position = .absolute, .inset = ui.Inset{ .right = .{ .px = args.side }, .bottom = .{ .percent = 100 } }, .margin = .{ .top = 0, .right = 0, .bottom = 8, .left = 0 }, .z_index = 2, }, t); } });

//# yix-map ai_composer.yss
