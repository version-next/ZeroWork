// GENERATED FILE, do not edit: generated from review_style.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
const ui = @import("ui");
const Flag = bool;
const Width = ?f32;

pub const aliased = ui.paramStyle(struct { enabled: Flag, width: Width, pub const declared = &[_][]const u8{ "width", "gap", }; pub fn resolve(args: @This(), t: *const ui.theme.Values) ui.BoxStyle { var out = ui.boxFrom(.{ .width = ui.orElse(args.width, .fit), }, t); if (args.enabled) out = out.merge(ui.boxFrom(.{ .gap = 3, }, t)); return out; } });

// LC3B: generated styles must compile keyword constants as f32, not enum literals.
pub const lc3_basis_auto = ui.previewCss("tests/yix/review_style.yss", "lc3_basis_auto", @embedFile("review_style.yss"), .{ .flex_basis = ui.FlexBasis.auto, });
pub const lc3_basis_content = ui.previewCss("tests/yix/review_style.yss", "lc3_basis_content", @embedFile("review_style.yss"), .{ .flex_basis = ui.FlexBasis.content, });
pub const lc3_basis_zero = ui.previewCss("tests/yix/review_style.yss", "lc3_basis_zero", @embedFile("review_style.yss"), .{ .flex_basis = 0, });
pub const lc3_lines = ui.previewCss("tests/yix/review_style.yss", "lc3_lines", @embedFile("review_style.yss"), .{ .align_content = .space_around, .align_self = .first_baseline, });

// LC3C: static compiler and live reload preserve CSS text break controls.
pub const lc3c_anywhere = ui.previewCss("tests/yix/review_style.yss", "lc3c_anywhere", @embedFile("review_style.yss"), .{ .wrap = .word, .overflow_wrap = .anywhere, });
pub const lc3c_break_all = ui.previewCss("tests/yix/review_style.yss", "lc3c_break_all", @embedFile("review_style.yss"), .{ .wrap = .word, .word_break = .break_all, });

// G17: token gradient endpoints, per interaction state.
pub const token_gradient = ui.previewCss("tests/yix/review_style.yss", "token_gradient", @embedFile("review_style.yss"), .{ .gradient = .{ .from = ui.tokenRef(.color, "accent"), .to = ui.tokenRef(.color, "bg-primary"), .direction = .diagonal }, ._hover = .{ .gradient = .{ .from = ui.tokenRef(.color, "bg-hover"), .to = ui.tokenRef(.color, "accent") }, }, ._active = .{ .gradient = .{ .from = ui.mix(ui.tokenRef(.color, "accent"), ui.tokenRef(.color, "bg-primary"), 0.5), .to = ui.Color.hex(0x102030), .direction = .horizontal }, }, });

//# yix-map review_style.yss
