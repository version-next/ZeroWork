//! Preferences window parameters, Island B v3 settings revamp (Pencil `p6ZVS`
//! and siblings): the native window's size and traffic-light placement, and
//! the category icons. The window itself is `settings_window.yix` (3f removed
//! the imperative shell that used to live here).
const std = @import("std");
const ui = @import("ui");
const pages = @import("../model/catalog.zig").pages;

/// Native window (`p6ZVS` and every subpage frame: 960 × 780).
pub const window = struct {
    pub const width: f32 = 960;
    pub const height: f32 = 780;
    pub const min_width: f32 = 760;
    pub const min_height: f32 = 480;
    /// Caption height handed to the platform: window padding 8 + nav padding 10 + window top 28.
    /// What drags the window is declared in the views (`nav.yix` title band, `header.yix`).
    pub const titlebar_height: f32 = 46;
    /// Traffic lights in `ZeTFX`: window 8 + nav padding 8 + row inset 6 +
    /// radius 6; top 8 + 10 + 28/2.
    pub const traffic_light_x: f32 = 28;
    pub const traffic_light_y: f32 = 32;
    pub const traffic_light_diameter: f32 = 12;
    /// `gq9c8`: three 12pt lights, gap 8.
    pub const traffic_lights_width: f32 = 52;
};

/// Auxiliary-window parameters for the preferences window.
pub const window_spec: @import("../../../shared/ui/window/aux_window.zig").Spec = .{
    .title = "设置",
    .width = @intFromFloat(window.width),
    .height = @intFromFloat(window.height),
    .min_width = @intFromFloat(window.min_width),
    .min_height = @intFromFloat(window.min_height),
    .titlebar_height = window.titlebar_height,
    .traffic_light_x = window.traffic_light_x,
    .traffic_light_y = window.traffic_light_y,
    .traffic_light_diameter = window.traffic_light_diameter,
    .maximizable = true,
};

/// Category icons, in `settings_pages.pages` order (`Bt1FV` › Categories).
pub const icons = [_]ui.SvgAsset{ ui.icons.palette, ui.icons.keyboard, ui.icons.network, ui.icons.arrow_down_up, ui.icons.sparkles, ui.icons.plug, ui.icons.bell, ui.icons.database, ui.icons.refresh_cw };
comptime {
    std.debug.assert(icons.len == pages.pages.len);
}
