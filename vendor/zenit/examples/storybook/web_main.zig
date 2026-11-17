//! zenit Storybook for the browser (Web DOM host): the same `mountUI` and stories
//! as the native app, mirrored to DOM. Built by `zig build web-storybook`
//! (zig-out/web/storybook). Stories are picked from the sidebar (`nav.<key>`).
//!
//! Window layout: the shim's build_environment presents the macOS (appkit) window
//! design, so story panels have the native width and can be compared pixel for
//! pixel with the native Storybook (e2e/web-storybook-parity).
const std = @import("std");
const ui = @import("ui");
const zenit_app = @import("zenit_app");
const storybook = @import("main.zig");
const stories = @import("stories.zig");

pub const panic = ui.web.panic;
pub const std_options_debug_io = ui.web.io;
comptime {
    ui.web.exportApp(@This());
}

var font_registry: ?zenit_app.FontRegistry = null;

pub fn mount(cx: *ui.Cx, scope: *ui.Scope) anyerror!*ui.Node {
    const a = std.heap.wasm_allocator;
    // Same font registry setup as native main(): the cjkweights fixture's Latin family.
    font_registry = zenit_app.FontRegistry.init(a);
    const cjk = @import("cjk_weights/mod.zig");
    std.debug.assert(@backingInt(try font_registry.?.intern(cjk.latin_family_name)) == cjk.latin_family_id);
    // BlendLab 32x32 checkerboard (8px squares), same image as native main().
    {
        var px: [32 * 32 * 4]u8 = undefined;
        for (0..32) |y| for (0..32) |x| {
            const val: u8 = if (((x / 8) + (y / 8)) % 2 == 0) 0 else 255;
            const o = (y * 32 + x) * 4;
            px[o] = val;
            px[o + 1] = val;
            px[o + 2] = val;
            px[o + 3] = 255;
        };
        var ir: zenit_app.ImageRenderer = .{};
        stories.g_blend_checker_texture = ir.loadTexture(32, 32, &px) catch null;
    }
    return storybook.mountUI(cx, scope);
}
