/// Per-frame redraw flag: markRenderDirty() in the on_before_render hook sets it, telling
/// Cx that active animations need rendering next frame.
///
/// Thread safety: main (UI) thread only; safe under the current single-threaded architecture.
/// Multi-threaded rendering would need an atomic or instance field.
pub var requested: bool = false;

const std = @import("std");
const builtin = @import("builtin");
var single_thread_hook: ?*HookScope = null;
threadlocal var thread_hook: ?*HookScope = null;

fn hookSlot() *?*HookScope {
    return if (comptime builtin.single_threaded) &single_thread_hook else &thread_hook;
}

/// Invocation-local continuation policy. A nested hook restores its caller's
/// policy; no Node layout or callback registration is changed.
pub const HookScope = struct {
    owner: *const anyopaque = undefined,
    function: usize = 0,
    continues: bool = true,
    previous: ?*HookScope = null,

    pub fn enter(self: *HookScope, owner: *const anyopaque, function: usize) void {
        self.* = .{ .owner = owner, .function = function, .previous = hookSlot().* };
        hookSlot().* = self;
    }

    pub fn leave(self: *HookScope) void {
        std.debug.assert(hookSlot().* == self);
        hookSlot().* = self.previous;
    }
};

/// Dirty marks from this exact managed hook update the current paint. Future
/// work must use requestRedraw or a deadline. Direct calls, other nodes and
/// wrapper hooks cannot accidentally consume their caller's continuation.
pub fn consumeCurrentFrame(owner: *const anyopaque, function: usize) void {
    const scope = hookSlot().* orelse return;
    if (scope.owner == owner and scope.function == function) scope.continues = false;
}
