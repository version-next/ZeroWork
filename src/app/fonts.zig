//! 界面字体校验与等宽字体安装（P2 自 src/main.zig 原样拆出）。

const std = @import("std");
const applog = @import("../platform/applog.zig");
const App = @import("zenit_app").App;

/// Terminal cell geometry depends on a TRUE monospace font: the VT grid maps
/// 1 column = 1 advance, and syncGridSize derives cols from the measured
/// advance. Zenit's stock macOS FontSelector never registers the mono group
/// (mono_count stays 0), so `use_monospace` silently fell back to the
/// proportional UI font (Helvetica Neue) — its wide "M" advance (~11.6px at
/// 13pt) inflated every cell, halved the visible column count and rendered
/// the terminal with visible inter-glyph gaps. Registering Menlo in the mono
/// slots (regular/bold/italic/bold-italic) makes selectMonospaceWeighted
/// return a real fixed-advance face for both shaping and rendering.
// Exercise the renderer selector, contextual and legacy measurement hooks,
// and the same shaped run used by input caret/selection in test builds.
pub fn verifyUiFontPaths(app: *App) !void {
    const samples = [_][]const u8{ "Local Terminal", "worker 为什么反复重启？先检查日志。", "Inter caret ssdf 🈶" };
    const actual = app.fonts[0].debugName(std.heap.c_allocator) orelse return error.UiFontUnavailable;
    defer std.heap.c_allocator.free(actual);
    applog.info(.app, "UI font actual={s} family={s}", .{ actual, app.resolved_font_family orelse "missing" });
    for (samples) |sample| {
        const size: f32 = 11.5;
        const draw = app.font_selector.measureTextWidthWithProps(sample, .{ .font_size = size });
        const contextual = app.cx.text.measure_ctx_fn.?(app.cx.text.measure_ctx.?, sample.ptr, sample.len, size, 400, false);
        const legacy = app.cx.text.measure_fn.?(sample.ptr, sample.len, size, 400, false);
        const shaped = app.cx.text.measureTextWidth(sample, size, 400, false);
        applog.info(.app, "UI font paths text={s} draw={d:.4} context={d:.4} legacy={d:.4} shaped={d:.4}", .{ sample, draw, contextual, legacy, shaped });
        if (@abs(draw - contextual) > 0.05 or @abs(draw - legacy) > 0.05 or @abs(draw - shaped) > 0.05) return error.UiFontPathMismatch;
    }
}

pub fn installMonospaceFonts(app: *App) void {
    const Presence = struct {
        extern fn coretext_family_exists(family: [*:0]const u8) c_int;
    };
    // CoreText may return a proportional substitute for an absent family.
    // Check availability before registering the shared command/log font role.
    const family: [:0]const u8 = if (Presence.coretext_family_exists("JetBrains Mono") != 0) "JetBrains Mono" else "Menlo";
    app.font_selector.mono_count = 0;
    app.font_selector.mono_bold_count = 0;
    app.font_selector.mono_italic_count = 0;
    app.font_selector.mono_bold_italic_count = 0;
    // findFont's descriptor is a struct literal: the enum field values
    // (.regular/.bold/.normal/.italic) coerce to the backend's own
    // FontWeight/FontStyle, so no type import is needed.
    const attempts = [_]struct { size: f32, bold: bool, italic: bool }{
        .{ .size = 13, .bold = false, .italic = false },
        .{ .size = 13, .bold = true, .italic = false },
        .{ .size = 13, .bold = false, .italic = true },
        .{ .size = 13, .bold = true, .italic = true },
        .{ .size = 14, .bold = false, .italic = false },
        .{ .size = 14, .bold = true, .italic = false },
    };
    for (attempts) |attempt| {
        const font = app.font_manager.findFont(.{
            .family = family,
            .size = attempt.size,
            .weight = if (attempt.bold) .bold else .regular,
            .style = if (attempt.italic) .italic else .normal,
        }) catch continue;
        font.setScaleFactor(app.scale);
        if (attempt.bold and attempt.italic) {
            if (app.font_selector.mono_bold_italic_count == 0) {
                app.font_selector.mono_bold_italic_fonts[0] = font;
                app.font_selector.mono_bold_italic_count = 1;
            }
        } else if (attempt.italic) {
            if (app.font_selector.mono_italic_count == 0) {
                app.font_selector.mono_italic_fonts[0] = font;
                app.font_selector.mono_italic_count = 1;
            }
        } else if (attempt.bold) {
            if (app.font_selector.mono_bold_count < app.font_selector.mono_bold_fonts.len) {
                app.font_selector.mono_bold_fonts[app.font_selector.mono_bold_count] = font;
                app.font_selector.mono_bold_count += 1;
            }
        } else {
            if (app.font_selector.mono_count < app.font_selector.mono_fonts.len) {
                app.font_selector.mono_fonts[app.font_selector.mono_count] = font;
                app.font_selector.mono_count += 1;
            }
        }
    }
    applog.info(.app, "monospace slots: mono={d} bold={d} italic={d} bold_italic={d}", .{
        app.font_selector.mono_count,
        app.font_selector.mono_bold_count,
        app.font_selector.mono_italic_count,
        app.font_selector.mono_bold_italic_count,
    });
}
