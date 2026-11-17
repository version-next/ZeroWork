//! AI composer tool row constants (Pencil Kaf7E A3 / ⑤ / O1–O4 / O6) the view-model measures
//! with; the row's and popovers' layout is `ai_composer_controls.yss`.
const ui = @import("ui");
pub const theme = @import("../../../../shared/ui/theme/app_theme.zig");
pub const Kind = enum { attachment, permission, model, effort, usage, execution };
/// Tool row: 2 apart (Kaf7E A3 Toolbar gap 2); the Textarea footer row pads it.
pub const row_gap: f32 = 2;
pub const ring_size: f32 = 12;
/// Menu / popover widths: O1 240, O2 280, O3 300, O4 320, O6 288.
pub fn width(kind: Kind) f32 {
    return switch (kind) {
        .attachment => 240,
        .permission => 280,
        .execution => 300,
        .model, .effort => 320,
        .usage => 288,
    };
}
pub fn height(kind: Kind) f32 {
    return switch (kind) {
        .model, .effort => 360,
        .usage => 420,
        else => 360,
    };
}
/// Tone of usage part n (W.ProgressSegments and its legend dot): fg-tertiary, accent, success, cycling.
pub fn usageTone(index: usize) ui.widgets.ProgressTone {
    return switch (index % 3) {
        0 => .neutral,
        1 => .accent,
        else => .success,
    };
}
/// Remote picker inputs (ai_remote_picker.zig) keep their compact 11.5 text.
pub fn tuneInput(input: *ui.widgets.input.InputResult) void {
    input.state.font_size = 11.5;
    input.state.line_height = 17;
    input.state.char_width = 6.9;
    input.state.dirty = true;
    if (input.state.text_display_node) |node| if (node.getText()) |text_value| {
        var next = text_value;
        next.font_size = 11.5;
        next.line_height = 17.0 / 11.5;
        next.color = theme.current().fg_1;
        node.setText(next);
    };
}
