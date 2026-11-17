//! Restricted UI slots supplied by the host. Plugins receive neither the
//! application root nor the workspace or native protocol implementation.
const std = @import("std");
const ui = @import("ui");
const identity = @import("identity.zig");
const envelope = @import("../config/connection_envelope.zig");

/// Shared initial preference for password-capable connection editors.
/// Contributions use this default while retaining an explicit user opt-out.
pub const default_save_password = true;

pub const SubmitIntent = enum { save, save_and_open, temporary, probe };
pub const EditorEvents = struct {
    context: *anyopaque,
    changed: *const fn (*anyopaque) void,
    submit: *const fn (*anyopaque, envelope.Envelope, SubmitIntent) anyerror!void,
    /// The host commits staging only after its existing config transaction
    /// succeeds. The opaque receipt never contains password bytes or a fake
    /// session owner; temporary credentials go to the real create operation.
    submit_with_secret: ?*const fn (*anyopaque, envelope.Envelope, SubmitIntent, @import("editor_credentials.zig").Handoff) anyerror!void = null,
    dismiss: ?*const fn (*anyopaque) void = null,
    cancelled: ?*const fn (*anyopaque) void = null,
};
pub const EditorProtocolPicker = struct {
    context: *anyopaque,
    mount: *const fn (*anyopaque, *ui.Cx, *ui.Scope) anyerror!*ui.Node,
};
pub const EditorMount = struct {
    cx: *ui.Cx,
    scope: *ui.Scope,
    slot: *ui.Node,
    protocol_id: []const u8,
    save_password_by_default: bool = default_save_password,
    /// Shared host component, instantiated in the editor scope.
    protocol_picker: ?EditorProtocolPicker = null,
    initial: ?envelope.Envelope = null,
    draft_revision: u64,
    events: EditorEvents,
    editor_host: ?*@import("content_context.zig").EditorHost = null,
    editor_id: u64 = 0,
    /// Set when this editor is a nested child opened for its parent. The
    /// subject is borrowed for the mount call only.
    child: ?ChildMount = null,
    credentials: ?@import("editor_credentials.zig").Facade = null,
    probes: ?@import("probe_contract.zig").EditorProbes = null,
    connection_configs: ?@import("connection_config_resolver.zig").Resolver = null,
};
pub const ChildMount = struct { intent: @import("content_context.zig").ChildIntent, subject: []const u8 = "" };
pub const ModalPresentation = struct {
    width: f32,
    title: []const u8,
    warning: bool = false,
};
pub const EditorInstance = struct {
    context: *anyopaque,
    vtable: *const VTable,
    handles_actions: bool = false,
    pub const VTable = struct {
        snapshot: *const fn (*anyopaque, std.mem.Allocator) anyerror!envelope.Envelope,
        clear_secrets: *const fn (*anyopaque) void,
        unmount: *const fn (*anyopaque) void,
        cancel: ?*const fn (*anyopaque) void = null,
        /// Optional presentation preference for a compact confirmation state.
        /// The host owns centering, viewport clamping and the modal itself.
        preferred_modal_height: ?*const fn (*anyopaque) ?f32 = null,
        /// Provider-owned confirmation copy and size; host still owns the shell.
        modal_presentation: ?*const fn (*anyopaque) ModalPresentation = null,
        /// Retain the editor scope and draft while a portaled child replaces
        /// the parent's visible dialog. Host evaluates this at layout safety.
        parent_presentation_visible: ?*const fn (*anyopaque) bool = null,
        visibility_changed: ?*const fn (*anyopaque, bool) void = null,
        child_completed: ?*const fn (*anyopaque, @import("content_context.zig").ChildCompletion) void = null,
    };
};
pub const EditorFactory = struct {
    context: ?*anyopaque = null,
    /// Existing SSH/SFTP share the fully featured editor supplied by the host.
    /// The contribution chooses that shared editor; protocol IDs do not.
    mount: ?*const fn (?*anyopaque, EditorMount) anyerror!EditorInstance = null,
    shared_editor: ?[]const u8 = null,
};
pub const ContentMount = struct {
    cx: *ui.Cx,
    scope: *ui.Scope,
    slot: *ui.Node,
    owner: identity.SessionHandle,
    connection: envelope.Envelope,
    content_context: ?*@import("content_context.zig").Context = null,
    frame_sink: ?*@import("frame_texture_sink.zig").Sink = null,
    service_access: ?@import("session_service_access.zig").SessionServiceAccess = null,
};
pub const ContentUpdate = struct {
    owner: identity.SessionHandle,
    revision: u64,
    title: []const u8,
    status: []const u8,
};
pub const RendererInstance = struct {
    context: *anyopaque,
    vtable: *const VTable,
    pub const VTable = struct {
        update: *const fn (*anyopaque, ContentUpdate) anyerror!void,
        focus_changed: *const fn (*anyopaque, bool) void,
        unmount: *const fn (*anyopaque) void,
        /// Presentation readiness does not imply an online remote service.
        /// Labels are borrowed for the synchronous host projection only.
        connection_status: ?*const fn (*anyopaque) ConnectionStatus = null,
        /// Open the renderer's existing connection diagnostics for the shared
        /// status-bar connection/route entries.
        show_connection_details: ?*const fn (*anyopaque) void = null,
        /// The content's side of the tab's floating AI launcher (Pencil j8WXoF D): its bounds,
        /// where its fixed top chrome ends and whether the remote keyboard / mouse is captured.
        launcher_context: ?*const fn (*anyopaque) LauncherContext = null,
        /// Host -> content: where the launcher rests (its corner and window rect) when this
        /// content occupies that corner; null otherwise. The launcher never moves for the
        /// content's overlays — they give way to it.
        place_launcher: ?*const fn (*anyopaque, ?LauncherPlacement) void = null,
    };
};
/// Window coordinates.
pub const LauncherRect = struct { x: f32, y: f32, w: f32, h: f32 };
pub const LauncherCorner = enum { bottom_right, bottom_left, top_right, top_left };
pub const LauncherContext = struct {
    /// The content's window rect; null = not on screen.
    bounds: ?LauncherRect = null,
    /// Bottom edge of fixed chrome at the content's top (KVM toolbar); the launcher's top
    /// corners rest 12 below it. null = none.
    top_chrome_bottom: ?f32 = null,
    /// The remote picture while it holds the keyboard and mouse; a launcher over it yields
    /// (fades out, lets the pointer through). null = not captured.
    captured: ?LauncherRect = null,
};
pub const LauncherPlacement = struct { corner: LauncherCorner, rect: LauncherRect };
pub const ConnectionStatus = struct {
    state: enum { connecting, online, degraded, ended },
    label: []const u8,
};
pub const RendererDefinition = struct {
    kind: []const u8,
    context: ?*anyopaque = null,
    /// Shared terminal/file renderers stay bound by the existing engine bridge.
    mount: ?*const fn (?*anyopaque, ContentMount) anyerror!RendererInstance = null,
    shared_renderer: bool = false,
    supports_window_transfer: bool = false,
};

pub const ContentServices = struct {
    content_context: ?*@import("content_context.zig").Context = null,
    frame_sink: ?*@import("frame_texture_sink.zig").Sink = null,
    service_access: ?@import("session_service_access.zig").SessionServiceAccess = null,
};
pub const ContentServicesFactory = struct {
    context: *anyopaque,
    create: *const fn (*anyopaque, identity.SessionHandle) anyerror!ContentServices,
};
