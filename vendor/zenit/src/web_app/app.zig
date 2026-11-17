//! `zenit_app` for the browser (Web DOM host). Same names as the native
//! package so desktop app code compiles unchanged for wasm32; the browser
//! drives frames (ui.web runtime), so the run-loop entry points here are
//! cheap no-ops and the window/surface APIs are inert.
//!
//! Wired by `zenit.addWebApp` as the app's `zenit_app` import.
const std = @import("std");
const ui = @import("ui");

extern "zenit" fn load_texture(ptr: [*]const u8, len: usize, w: u32, h: u32) u32;
extern "zenit" fn font_family(id: u16, ptr: [*]const u8, len: usize) void;

pub const gpu_layer = struct {};

pub const FrameStats = struct {
    cpu_frame_us: u64 = 0,
    gpu_frame_us: u64 = 0,
    layout_us: u64 = 0,
    render_us: u64 = 0,
    encode_us: u64 = 0,
    draw_calls: u32 = 0,
};

pub const ImageRenderer = struct {
    /// RGBA8 straight alpha, row-major. Returns the texture id used by image
    /// nodes (`ui.image(cx, id)`); the browser keeps the bitmap.
    pub fn loadTexture(_: *ImageRenderer, w: u32, h: u32, rgba: []const u8) !u32 {
        if (rgba.len < @as(usize, w) * h * 4) return error.InvalidImage;
        const id = load_texture(rgba.ptr, rgba.len, w, h);
        if (id == 0) return error.TextureUploadFailed;
        return id;
    }
    pub fn unloadTexture(_: *ImageRenderer, _: u32) void {}
};

pub const TextRenderer = struct {};

pub const Renderer = struct {
    image_renderer: ImageRenderer = .{},
    text_renderer: TextRenderer = .{},
    pub fn getLastFrameStats(_: *const Renderer) FrameStats {
        return .{};
    }
    pub fn requestCapture(_: *Renderer, _: []const u8) bool {
        return false;
    }
};

pub const Window = struct {
    pub fn setTrafficLightsInset(_: *Window, _: f32, _: f32) void {}
    pub fn setAcceptsMouseWhileInactive(_: *Window, _: bool) void {}
    pub fn setTitle(_: *Window, _: []const u8) void {}
};

pub const Sdk = struct {
    pub const PumpResult = struct { requested_redraw: bool = false, quit: bool = false };
    pub fn pump(_: *Sdk, _: anytype) error{}!PumpResult {
        return .{};
    }
    pub fn events(_: *Sdk) []const @import("system_sdk").events.Event {
        return &.{};
    }
};

pub const FontManager = struct {};

/// Font families by name. Measurement and paint use the browser's font stack;
/// names are forwarded so CSS / canvas can resolve the same family.
pub const FontRegistry = struct {
    allocator: std.mem.Allocator,
    names: std.ArrayListUnmanaged([]u8) = .empty,
    scale_factor: f32 = 1.0,
    /// Same shape as native (an opaque enum over the family index).
    pub const FamilyId = enum(u16) { _ };
    pub const Resolved = struct { scale_factor: f32 = 1.0 };

    pub fn init(allocator: std.mem.Allocator) FontRegistry {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *FontRegistry) void {
        for (self.names.items) |n| self.allocator.free(n);
        self.names.deinit(self.allocator);
    }
    pub fn setFontSystem(_: *FontRegistry, _: *FontManager) void {}
    pub fn intern(self: *FontRegistry, name: []const u8) !FamilyId {
        for (self.names.items, 0..) |n, i| if (std.mem.eql(u8, n, name)) return @enumFromInt(i + 1);
        try self.names.append(self.allocator, try self.allocator.dupe(u8, name));
        const id: u16 = @intCast(self.names.items.len);
        font_family(id, name.ptr, name.len);
        return @enumFromInt(id);
    }
    pub fn resolve(_: *FontRegistry, _: FamilyId, _: f32, _: u16, _: bool) ?Resolved {
        return .{};
    }
};

pub const AppConfig = struct {
    io: ?std.Io = null,
    window: struct { title: []const u8 = "", width: f32 = 0, height: f32 = 0 } = .{},
};

pub const App = struct {
    allocator: std.mem.Allocator,
    cx: *ui.Cx,
    renderer: Renderer = .{},
    font_manager: FontManager = .{},
    win: Window = .{},
    sdk: Sdk = .{},
    viewport_w: f32 = 0,
    viewport_h: f32 = 0,
    should_quit: bool = false,

    /// Wraps the runtime's Cx (created by ui.web before the app mounts).
    pub fn init(allocator: std.mem.Allocator, _: anytype) !*App {
        const s = ui.web.state orelse return error.WebRuntimeNotStarted;
        const app = try allocator.create(App);
        app.* = .{ .allocator = allocator, .cx = s.cx, .viewport_w = s.cx.viewport.width, .viewport_h = s.cx.viewport.height };
        return app;
    }
    pub fn deinit(self: *App) void {
        self.allocator.destroy(self);
    }
    /// Builds the root view; the web runtime picks it up as cx.root.
    pub fn mount(self: *App, comptime mountFn: anytype) !void {
        const s = ui.web.state orelse return error.WebRuntimeNotStarted;
        const root = try mountFn(self.cx, s.scope);
        self.cx.root = root;
    }
    pub fn setFontRegistry(_: *App, _: *FontRegistry) void {}
    /// Browser-driven: the runtime renders after beforeFrame returns.
    pub fn frame(self: *App) !void {
        self.syncViewport();
    }
    pub fn processEvents(_: *App) void {}
    pub fn processEvent(_: *App, _: anytype) bool {
        return false;
    }
    pub fn maybeReconfigureSurface(self: *App) !void {
        self.syncViewport();
    }
    fn syncViewport(self: *App) void {
        self.viewport_w = self.cx.viewport.width;
        self.viewport_h = self.cx.viewport.height;
    }
};

/// Window chrome contract (shared with native). The browser has no native window
/// backend: web builds present the macOS (appkit) window design, the parity
/// target for pixel comparison with the native apps.
pub const window_chrome = @import("system_sdk").window_chrome;
pub const build_environment = .{
    .os = @import("builtin").os.tag,
    .window_backend = window_chrome.WindowBackend.appkit,
};

/// Dev-preview control plane and e2e test harness are native-only.
pub const dev_control = struct {
    pub const enabled = false;
    pub fn active() bool {
        return false;
    }
    pub fn persist(_: []const u8, _: u32, _: anytype, _: anytype, _: anytype) !void {}
    pub fn unpersist(_: []const u8) !void {}
    pub fn markDirty() void {}
};
pub const test_harness = struct {
    pub const enabled = false;
    pub fn setAppRouteHandler(_: anytype) void {}
};
pub const MultiWindowApp = struct {};

pub fn run(_: anytype, _: anytype) !void {}
pub fn setTestRouteHandler(_: anytype) void {}
pub fn drainTestCommands() void {}
