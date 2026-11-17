//! Declarative focus for one window (`Cx.focus_targets`): named focus targets (`focusId`),
//! initial focus (`autoFocus`), view-model focus requests (`focusRequest`) and focus restore
//! after a subtree remount (`focusRestore`). Design: docs/FOCUS_AND_KEY_CAPTURE_DESIGN.md.
//!
//! Everything here ends in an ordinary programmatic focus transition through FocusManager, so
//! focus/blur events, a11y notification, the native text-input session and the focus ring
//! behave as for `cx.setFocus`. Pending work (a target that is not mounted, shown or enabled
//! yet) waits in this registry and is retried at the start of every frame (`settle`, called by
//! Cx.render next to the overlay focus restore). Any focus transition that happens after a
//! pending item was recorded supersedes it (last writer wins, compared by
//! FocusManager.transition_epoch); silent focus loss (node teardown) is not a transition.
//!
//! Registration owns no node: entries keep the node pointer plus an identity handle and are
//! dropped by the mounting scope (view.zig). The pointer is dereferenced only after the
//! identity check (`NodeRegistry.isCurrentIdentity`), which never dereferences it.
const std = @import("std");
const Allocator = std.mem.Allocator;
const core = @import("core.zig");
const Node = core.Node;
const NodeHandle = core.NodeHandle;
const Cx = core.Cx;
const types = @import("core/types.zig");
const focus_mod = @import("focus.zig");

pub const Kind = enum {
    /// `focusId`: a named focus target (optionally with a pending `autoFocus`).
    target,
    /// `focusRestore`: remembers the focused target inside it across a remount.
    region,
    /// `focusRequest`: scope for view-model focus requests.
    requester,
};

const Entry = struct {
    token: u32,
    kind: Kind,
    node: *Node,
    identity: NodeHandle,
    /// Owned; targets only.
    name: []u8 = &.{},
    /// autoFocus still pending: the transition epoch at registration.
    auto_epoch: ?u64 = null,
    /// autoFocus inside a closed auto-focus trap scope (a Modal / Sheet mounted closed): the
    /// target is focused each time that scope is pushed (`FocusObserver.entry_target`)
    /// instead of at mount.
    scope_auto: bool = false,
};

/// Where focus is now, by name: the nearest named target around the focused node and the
/// nearest restore region around that target.
const Current = struct {
    node_id: u32,
    name: []u8,
    region: u32,
};

/// A named target lost focus to teardown inside a restore region.
const Lost = struct {
    name: []u8,
    region: u32,
    selection: ?types.TextInputSelection,
    visible: bool,
    /// Transition epoch after the loss; null until sealed (see noteRemoved).
    epoch: ?u64,
};

const Request = struct {
    name: []u8,
    requester: u32,
    epoch: u64,
};

pub const FocusTargets = struct {
    allocator: Allocator,
    entries: std.ArrayList(Entry) = .empty,
    next_token: u32 = 1,
    current: ?Current = null,
    lost: ?Lost = null,
    request: ?Request = null,

    pub fn init(allocator: Allocator) FocusTargets {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *FocusTargets) void {
        for (self.entries.items) |e| self.allocator.free(e.name);
        self.entries.deinit(self.allocator);
        self.entries = .empty;
        self.clearCurrent();
        self.clearLost();
        self.clearRequest();
    }

    /// Anything to do at the next frame start.
    pub fn hasPending(self: *const FocusTargets) bool {
        if (self.lost != null or self.request != null) return true;
        for (self.entries.items) |e| if (e.auto_epoch != null) return true;
        return false;
    }

    /// Register `node`. `name` is copied (targets). `auto_focus` arms a pending autoFocus.
    /// Returns the token for `unregister`.
    pub fn register(self: *FocusTargets, cx: *Cx, kind: Kind, node: *Node, name: []const u8, auto_focus: bool) !u32 {
        const generation = try cx.node_registry.trackGeneration(node);
        const owned: []u8 = if (kind == .target) try self.allocator.dupe(u8, name) else &.{};
        errdefer self.allocator.free(owned);
        const token = self.next_token;
        try self.entries.append(self.allocator, .{
            .token = token,
            .kind = kind,
            .node = node,
            .identity = .{ .id = node.id, .generation = generation },
            .name = owned,
            .auto_epoch = if (auto_focus) cx.focus_manager.transition_epoch else null,
        });
        self.next_token +%= 1;
        if (self.next_token == 0) self.next_token = 1;
        if (auto_focus) cx.requestRedraw();
        return token;
    }

    pub fn unregister(self: *FocusTargets, token: u32) void {
        for (self.entries.items, 0..) |e, i| {
            if (e.token != token) continue;
            self.allocator.free(e.name);
            _ = self.entries.orderedRemove(i);
            return;
        }
    }

    /// The `focusId` of the nearest named focus target at or around `node` (the name an app gave
    /// the control `node` belongs to), or null. Lets a host tell which of its controls a node is
    /// -- typically the focused node -- by the same name `focusRequest` / `focusRestore` use,
    /// instead of by the node's test id or its place in the tree. The slice is owned by the
    /// registry: valid until that target is unmounted.
    pub fn targetName(self: *const FocusTargets, cx: *Cx, node: *const Node) ?[]const u8 {
        var cur: ?*const Node = node;
        while (cur) |n| : (cur = n.parent) {
            for (self.entries.items) |e| {
                if (e.kind == .target and e.node == n and e.name.len != 0 and self.alive(cx, e)) return e.name;
            }
        }
        return null;
    }

    /// `focusRequest` changed: focus the target named `name` inside the requester's subtree
    /// now if it is ready, else keep the request pending. null clears focus when it is inside
    /// the requester's subtree. Either way an older pending request is dropped.
    pub fn requestFocus(self: *FocusTargets, cx: *Cx, requester: u32, name: ?[]const u8) void {
        self.clearRequest();
        const scope = self.liveNode(cx, requester) orelse return;
        const fm = &cx.focus_manager;
        const id = name orelse {
            if (fm.getFocused()) |focused| if (within(focused, scope)) fm.clearFocus();
            return;
        };
        if (self.findReady(cx, scope, id)) |node| {
            fm.setFocus(node);
            return;
        }
        const owned = self.allocator.dupe(u8, id) catch return;
        self.request = .{ .name = owned, .requester = requester, .epoch = fm.transition_epoch };
        cx.requestRedraw();
    }

    /// Run pending work, in priority order: view-model request, restore, autoFocus. Each one
    /// that focuses something supersedes the rest (they require no transition since).
    pub fn settle(self: *FocusTargets, cx: *Cx) void {
        if (self.entries.items.len == 0 and self.lost == null and self.request == null) return;
        const fm = &cx.focus_manager;
        if (self.request) |req| {
            if (req.epoch != fm.transition_epoch) {
                self.clearRequest();
            } else if (self.liveNode(cx, req.requester)) |scope| {
                if (self.findReady(cx, scope, req.name)) |node| {
                    self.clearRequest();
                    fm.setFocus(node);
                }
            } else self.clearRequest();
        }
        if (self.lost) |lost| {
            const epoch = lost.epoch orelse fm.transition_epoch;
            if (epoch != fm.transition_epoch or fm.getFocused() != null) {
                self.clearLost();
            } else if (self.liveNode(cx, lost.region)) |region| {
                if (self.findReady(cx, region, lost.name)) |node| {
                    const selection = lost.selection;
                    const visible = lost.visible;
                    self.clearLost();
                    fm.setFocusWithVisibility(node, .programmatic, if (visible) .show else .hide);
                    if (selection) |sel| if (fm.getFocused() == node) restoreSelection(node, sel);
                }
            } else self.clearLost();
        }
        // An active scope still settling its entry owns the autoFocus targets inside it
        // (`entryTarget`), so its named initial focus is not overtaken.
        const entering = fm.pendingEntryScope();
        var i: usize = 0;
        while (i < self.entries.items.len) : (i += 1) {
            const e = &self.entries.items[i];
            const epoch = e.auto_epoch orelse continue;
            if (epoch != fm.transition_epoch or !self.alive(cx, e.*)) {
                e.auto_epoch = null;
                continue;
            }
            if (entering) |scope| if (within(e.node, scope)) continue;
            const node = ready(cx, e.node) orelse {
                if (insideInactiveTrap(cx, e.node)) {
                    e.auto_epoch = null;
                    e.scope_auto = true;
                }
                continue;
            };
            e.auto_epoch = null;
            // Inside a focus-trapping scope (a Popover / Modal open when it mounted): the scope's
            // default on every later entry too, as when it mounted closed.
            if (insideTrapScope(e.node)) e.scope_auto = true;
            fm.setFocus(node);
            // The registry may have changed under focus callbacks; the transition already
            // superseded every other autoFocus.
            break;
        }
    }

    // ---- Focus observation (FocusManager.observer) ----

    pub fn observer(cx: *Cx) focus_mod.FocusObserver {
        return .{ .context = @ptrCast(cx), .focused = &observeFocused, .lost = &observeLost, .entry_target = &entryTarget, .find_target = &findTarget, .restamp = &restamp };
    }

    /// An auto-focus scope takes focus (FocusManager.pushScopeWith / settleScopeEntry; the trap
    /// refocus asks without requests or a name). In priority order:
    /// 1. a pending view-model request whose requester contains the scope and whose target is
    ///    mounted in it: that target (not ready = wait). A request for a name not mounted anywhere
    ///    yet may still land in the scope: whatever the scope focuses meanwhile is a placeholder
    ///    (`later`), and the request keeps its turn (`settle`). A request for a target mounted
    ///    outside the scope is not about this scope.
    /// 2. the scope's named `initial` focus mounted in it: that target (not ready = wait); not
    ///    mounted in it (yet, or a stale name) = the default as a placeholder (`later`).
    /// 3. a ready autoFocus target inside (from then on the scope's default on every entry).
    /// 4. no declaration.
    fn entryTarget(context: *anyopaque, scope: *Node, query: focus_mod.EntryQuery) focus_mod.EntryTarget {
        const cx: *Cx = @ptrCast(@alignCast(context));
        const self = &cx.focus_targets;
        var later = false;
        if (query.requests) if (self.request) |req| if (req.epoch == cx.focus_manager.transition_epoch) {
            if (self.liveNode(cx, req.requester)) |requester| if (within(scope, requester)) {
                switch (self.placement(cx, scope, req.name)) {
                    .inside => {
                        if (self.findReady(cx, scope, req.name)) |node| {
                            self.clearRequest();
                            return .{ .focus = node };
                        }
                        return .wait;
                    },
                    .nowhere => later = true,
                    .outside => {},
                }
            };
        };
        if (query.initial) |name| switch (self.placement(cx, scope, name)) {
            .inside => {
                const node = self.findReady(cx, scope, name) orelse return .wait;
                return if (later) .{ .later = node } else .{ .focus = node };
            },
            .nowhere, .outside => later = true,
        };
        for (self.entries.items) |*e| {
            if (e.kind != .target or (e.auto_epoch == null and !e.scope_auto)) continue;
            if (!self.alive(cx, e.*) or !within(e.node, scope)) continue;
            const node = ready(cx, e.node) orelse continue;
            e.auto_epoch = null;
            // The scope's own default from now on, on every entry (a Popover / Modal reopened).
            e.scope_auto = true;
            return if (later) .{ .later = node } else .{ .focus = node };
        }
        return if (later) .{ .later = null } else .none;
    }

    const Placement = enum { inside, outside, nowhere };

    /// Where live targets named `name` are mounted relative to `scope` (inside wins).
    fn placement(self: *const FocusTargets, cx: *Cx, scope: *Node, name: []const u8) Placement {
        var result: Placement = .nowhere;
        for (self.entries.items) |e| {
            if (e.kind != .target or !std.mem.eql(u8, e.name, name) or !self.alive(cx, e)) continue;
            if (within(e.node, scope)) return .inside;
            result = .outside;
        }
        return result;
    }

    /// A scope entry's placeholder was the only transition (`FocusObserver.restamp`): pending
    /// work stamped before it is still current.
    fn restamp(context: *anyopaque, old: u64, new: u64) void {
        const cx: *Cx = @ptrCast(@alignCast(context));
        const self = &cx.focus_targets;
        if (self.request) |*r| if (r.epoch == old) {
            r.epoch = new;
        };
        if (self.lost) |*l| if (l.epoch) |epoch| if (epoch == old) {
            l.epoch = new;
        };
        for (self.entries.items) |*e| if (e.auto_epoch) |epoch| if (epoch == old) {
            e.auto_epoch = new;
        };
    }

    /// A ready target named `name` anywhere in the window (FocusManager return focus).
    fn findTarget(context: *anyopaque, name: []const u8) ?*Node {
        const cx: *Cx = @ptrCast(@alignCast(context));
        const root = cx.root orelse return null;
        return cx.focus_targets.findReady(cx, root, name);
    }

    fn observeFocused(context: *anyopaque, node: ?*Node) void {
        const cx: *Cx = @ptrCast(@alignCast(context));
        cx.focus_targets.noteFocused(cx, node);
    }

    fn observeLost(context: *anyopaque, node: *Node, read_client: bool) void {
        const cx: *Cx = @ptrCast(@alignCast(context));
        const self = &cx.focus_targets;
        self.noteLoss(cx, node, read_client);
        // Silent: no transition follows, so the loss is sealed at the current epoch.
        self.sealLoss(cx);
    }

    fn noteFocused(self: *FocusTargets, cx: *Cx, node: ?*Node) void {
        self.clearCurrent();
        const focused = node orelse return;
        if (self.entries.items.len == 0) return;
        var target: ?*const Entry = null;
        var region: u32 = 0;
        var cur: ?*Node = focused;
        while (cur) |n| : (cur = n.parent) {
            for (self.entries.items) |*e| {
                if (e.node != n or !self.alive(cx, e.*)) continue;
                if (target == null and e.kind == .target) target = e;
                if (target != null and region == 0 and e.kind == .region) region = e.token;
            }
            if (region != 0) break;
        }
        const t = target orelse return;
        if (region == 0) return;
        const name = self.allocator.dupe(u8, t.name) catch return;
        self.current = .{ .node_id = focused.id, .name = name, .region = region };
    }

    /// The focused node is being torn down (FocusManager silent paths, or the subtree
    /// invalidation that follows with clearFocus). Remember what to restore.
    fn noteLoss(self: *FocusTargets, cx: *Cx, node: *Node, read_client: bool) void {
        const cur = self.current orelse return;
        if (cur.node_id != node.id) return;
        self.current = null;
        self.clearLost();
        self.lost = .{
            .name = cur.name,
            .region = cur.region,
            .selection = if (read_client) readSelection(node) else null,
            .visible = cx.focus_manager.focus_visible,
            .epoch = null,
        };
        cx.requestRedraw();
    }

    /// Subtree invalidation is about to clear focus on `node` (a real transition). The node's
    /// callback context may already be disposed, so the text selection is not read; seal the
    /// loss with `sealLoss` after the transition.
    pub fn noteRemoved(self: *FocusTargets, cx: *Cx, node: *Node) void {
        self.noteLoss(cx, node, false);
    }

    pub fn sealLoss(self: *FocusTargets, cx: *Cx) void {
        if (self.lost) |*lost| if (lost.epoch == null) {
            lost.epoch = cx.focus_manager.transition_epoch;
        };
    }

    // ---- Lookup ----

    /// The registration's node still exists. A registration is owned by the scope that mounted
    /// the node and unregisters with it, so it follows the node across a retained detach and
    /// re-attach (`Cx.detachChildRetained` re-issues the node's handle generation on purpose, for
    /// input handles; a `focusId` / `focusRequest` declared in a panel that leaves the tree while
    /// closed must still work when it comes back). The registry drops a node's identity row when
    /// the node is freed and node ids are never reused, so the row's presence is the liveness test.
    fn alive(_: *const FocusTargets, cx: *Cx, e: Entry) bool {
        if (!cx.node_registry.generations.contains(e.identity.id)) return false;
        return !e.node.freeing and e.node.pending_free_cx == null;
    }

    fn liveNode(self: *const FocusTargets, cx: *Cx, token: u32) ?*Node {
        for (self.entries.items) |e| if (e.token == token) return if (self.alive(cx, e)) e.node else null;
        return null;
    }

    /// First ready target named `name` inside `scope` (scope included), in registration order.
    fn findReady(self: *const FocusTargets, cx: *Cx, scope: *Node, name: []const u8) ?*Node {
        for (self.entries.items) |e| {
            if (e.kind != .target or !std.mem.eql(u8, e.name, name) or !self.alive(cx, e)) continue;
            if (!within(e.node, scope)) continue;
            if (ready(cx, e.node)) |node| return node;
        }
        return null;
    }

    fn clearCurrent(self: *FocusTargets) void {
        if (self.current) |c| self.allocator.free(c.name);
        self.current = null;
    }

    fn clearLost(self: *FocusTargets) void {
        if (self.lost) |l| self.allocator.free(l.name);
        self.lost = null;
    }

    fn clearRequest(self: *FocusTargets) void {
        if (self.request) |r| self.allocator.free(r.name);
        self.request = null;
    }
};

/// `node` is `root` or inside it.
fn within(node: *Node, root: *Node) bool {
    var cur: ?*Node = node;
    while (cur) |n| : (cur = n.parent) if (n == root) return true;
    return false;
}

fn focusable(node: *const Node) bool {
    const i = node.behavior.interaction;
    return i.focusable or i.tab_index != null;
}

fn disabled(node: *const Node) bool {
    const a11y = node.behavior.interaction.a11y orelse return false;
    return a11y.disabled;
}

/// The node to focus for target `node` when it is ready: attached to this window's tree,
/// displayed, enabled, inside the active trap scope; itself when focusable, else its first
/// focusable, displayed, enabled descendant in tree order. null = not ready.
fn ready(cx: *Cx, node: *Node) ?*Node {
    var top = node;
    while (top.parent) |p| top = p;
    if (cx.root) |root| if (top != root) return null;
    if (!node.isDisplayedInTree() or disabled(node)) return null;
    const pick = firstFocusable(node) orelse return null;
    // Content of a closed dialog (its trap scope not pushed) waits for the dialog.
    if (!cx.focus_manager.keyboardReachable(pick)) return null;
    if (cx.focus_manager.activeScope()) |scope| {
        if (scope.behavior.interaction.focus_scope) |cfg| if (cfg.trap and !within(pick, scope)) return null;
    }
    return pick;
}

fn insideTrapScope(node: *const Node) bool {
    var cur: ?*const Node = node;
    while (cur) |n| : (cur = n.parent) {
        const cfg = n.behavior.interaction.focus_scope orelse continue;
        if (cfg.trap) return true;
    }
    return false;
}

fn insideInactiveTrap(cx: *Cx, node: *Node) bool {
    return node.isDisplayedInTree() and !cx.focus_manager.keyboardReachable(node);
}

fn firstFocusable(node: *Node) ?*Node {
    if (node.style.display == .none or disabled(node)) return null;
    if (focusable(node)) return node;
    for (node.children.items) |child| if (firstFocusable(child)) |n| return n;
    return null;
}

/// Only called on paths whose contract keeps the client context alive (FocusManager.abandonFocus).
fn readSelection(node: *Node) ?types.TextInputSelection {
    const client = node.behavior.interaction.text_input_client orelse return null;
    return client.selection(client.context);
}

fn restoreSelection(node: *Node, sel: types.TextInputSelection) void {
    const client = node.behavior.interaction.text_input_client orelse return;
    const set = client.set_selection orelse return;
    const len: u32 = @intCast(@min(client.text_len(client.context), std.math.maxInt(u32)));
    _ = set(client.context, @min(sel.start, len), @min(sel.end, len));
}
