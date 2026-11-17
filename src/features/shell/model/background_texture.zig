//! Main-thread GPU admission for already decoded background pixels. Keep the
//! old Texture alive until the shared configuration transaction has committed.
//!
//! The pixels go into the process-wide shared image store when the runtime has
//! one (`MultiWindowConfig.shared_gpu`, macOS / Windows): the same texture is
//! drawn by the owning main window (wallpaper) and by the separate preferences
//! window (背景缩略图 `settings.materials.preview.open` and the inline material
//! preview, S-18). A texture loaded through `app.renderer.image_renderer` is
//! window-local: its id resolves to nothing in any other window's renderer,
//! which left both previews blank in the preferences window.
const std = @import("std");
const App = @import("zenit_app").App;
const Prepared = @import("../../../config/background_asset.zig").Prepared;
const repeat = @import("background_repeat.zig");
const ImageTextureStore = @typeInfo(@typeInfo(@typeInfo(@TypeOf(App.sharedImageStore)).@"fn".return_type.?).optional.child).pointer.child;
const ImageRenderer = @FieldType(@typeInfo(@FieldType(App, "renderer")).pointer.child, "image_renderer");

/// Where a texture was loaded; it is released through the same store.
pub const Store = union(enum) {
    /// Process-wide store: ids resolve in every window of the runtime.
    shared: *ImageTextureStore,
    /// Fallback without a shared GPU (Linux): ids resolve only in the owning window.
    local: *ImageRenderer,

    pub fn of(app: *App) Store {
        return if (app.sharedImageStore()) |store| .{ .shared = store } else .{ .local = &app.renderer.image_renderer };
    }
    fn load(self: Store, width: u32, height: u32, rgba: []const u8) !u32 {
        return switch (self) {
            inline else => |store| store.loadTexture(width, height, rgba),
        };
    }
    fn unload(self: Store, id: u32) void {
        switch (self) {
            inline else => |store| store.unloadTexture(id),
        }
    }
};

pub const Texture = struct {
    app: *App,
    store: Store,
    id: u32,
    width: u32,
    height: u32,
    repeating: ?repeat.Texture = null,

    pub fn deinit(self: *Texture) void {
        if (self.repeating) |texture| self.store.unload(texture.id);
        self.store.unload(self.id);
        self.* = undefined;
    }
};

/// No file access or decoding here. GPU allocation/budget errors are returned
/// before settings persistence, so callers can retain their last good texture.
pub fn upload(app: *App, prepared: *const Prepared) !Texture {
    const image = prepared.image;
    if (image.width == 0 or image.height == 0) return error.InvalidImage;
    const pixels = try std.math.mul(usize, image.width, image.height);
    const bytes = try std.math.mul(usize, pixels, 4);
    if (image.pixels.len != bytes) return error.InvalidImage;
    const store = Store.of(app);
    const id = try store.load(image.width, image.height, image.pixels);
    errdefer store.unload(id);
    var repeating: ?repeat.Texture = null;
    if (try repeat.expand(app.allocator, image.width, image.height, image.pixels)) |expanded| {
        defer app.allocator.free(expanded.rgba);
        const repeated_id = try store.load(expanded.width, expanded.height, expanded.rgba);
        repeating = .{ .id = repeated_id, .width = expanded.width, .height = expanded.height };
    }
    return .{ .app = app, .store = store, .id = id, .width = image.width, .height = image.height, .repeating = repeating };
}
