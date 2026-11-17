// GENERATED FILE, do not edit: generated from styles.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! Grabber styling: a capsule in the tertiary ink at rest and the accent ink while its surface is
//! held (follows tokens, the same in every theme mode). View in grabber.yix.
const ui = @import("../../ui.zig");

/// Capsule 4 high (radius = half the height), `width` from the view (36 at rest, 48 held); never
/// shrinks, never hit.
pub const capsule = ui.paramStyle(struct { width: f32, pub const declared = &[_][]const u8{ "width", "height", "corner_radius", "flex_shrink", "hit_behavior", }; pub fn resolve(args: @This(), t: *const ui.theme.Values) ui.BoxStyle { return ui.boxFrom(.{ .width = args.width, .height = 4, .corner_radius = 2, .flex_shrink = 0, .hit_behavior = .pass_through, }, t); } });
/// Ink: `fg-tertiary` at rest, `accent` while the host's drag region is pressed (`active`).
pub const Ink = ui.previewCva("src/ui/components/grabber/styles.yss", "Ink", @embedFile("styles.yss"), .{ .base = .{ }, .variants = .{ .active = .{ .false = .{ .background = ui.tokenRef(.color, "fg-tertiary"), }, .true = .{ .background = ui.tokenRef(.color, "accent"), }, }, }, .defaults = .{ .active = false, }, });

//# yix-map styles.yss
