//! Host adaptation through the installed public TextareaResult/State fields.
//! Keep the native document, wrapping, IME and internal scrolling intact.
//! The composer is one native compound Textarea (header: attachments, footer: tool row); its
//! text uses the native md field metrics and grows from 1 to 6 lines through the native
//! `auto_rows` (Pencil Kaf7E ③ “输入框”).
const ui = @import("ui");
/// Textarea snapshots its palette at mount; retained drafts must follow theme
/// publication even while their panel is detached from the render tree.
pub fn bindTheme(cx: *ui.Cx, scope: *ui.Scope, input: ui.widgets.input.TextareaResult) !void {
    try scope.createEffect(.{ .cx = cx, .input = input, .publication = try cx.themeSignal() }, struct {
        fn paint(ctx: anytype) void {
            _ = ctx.publication.get();
            ctx.input.state.tokens = ctx.cx.tokens;
            ctx.input.state.dirty = true;
            ctx.input.input.markLayoutDirty();
        }
    }.paint);
}
/// Kept for callers that prepared the editor before mounting it; the native metrics stand.
pub fn configure(input: ui.widgets.input.TextareaResult) void {
    input.state.dirty = true;
}
