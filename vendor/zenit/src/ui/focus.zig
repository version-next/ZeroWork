/// Focus Manager
///
/// Manages UI node focus state:
/// - Tracks current focused node
/// - Tab navigation (forward/backward)
/// - Focus/blur events
/// - Focusable node registration
const std = @import("std");
const Allocator = std.mem.Allocator;
const core = @import("core.zig");
const Node = core.Node;
const NodeHandle = core.NodeHandle;
const NodeRegistry = core.NodeRegistry;
const events_mod = @import("events.zig");
const FocusReason = events_mod.FocusReason;
const FocusEvent = events_mod.FocusEvent;
const Event = events_mod.Event;
const event_dispatcher_mod = @import("event_dispatcher.zig");
const system_sdk = @import("system_sdk");
const A11yRole = core.A11yRole;

/// Focus Scope configuration
pub const FocusScopeConfig = struct {
    /// Whether focus trap (Tab cannot escape)
    trap: bool = false,
    /// Auto-focus first focusable node on scope entry
    auto_focus: bool = false,
};

/// Focus scope stack depth limit.
///
/// 64 far exceeds any realistic GUI scope nesting depth (macOS typically < 5 modal
/// layers); an unbounded ArrayList is not worth the callsite refactoring.
pub const SCOPE_STACK_CAP: usize = 64;
/// Scoped focus order buffer (v0.1-P6: 64->512)
pub const SCOPED_BUF_CAP: usize = 512;

/// Explicit visibility affects this focus request only; it does not change input modality.
pub const FocusVisibility = enum { inherit, show, hide };
pub const InputModality = enum { pointer, keyboard };

/// Observes committed focus changes and silent focus loss (Cx installs the declarative-focus
/// registry, focus_targets.zig). `focused` runs once a transition commits its new owner (null
/// for a transition to nothing); `lost` runs before a silent path drops the owner, with
/// `read_client` true only when the node's callback context is still alive (abandonFocus).
pub const FocusObserver = struct {
    context: *anyopaque,
    focused: *const fn (context: *anyopaque, node: ?*Node) void,
    lost: *const fn (context: *anyopaque, node: *Node, read_client: bool) void,
    /// What an auto-focus scope taking focus should focus (`pushScopeWith`, then each settle of
    /// its pending entry), see `EntryQuery` / `EntryTarget`. Null hook = no declarations (the
    /// first focusable node).
    entry_target: ?*const fn (context: *anyopaque, scope: *Node, query: EntryQuery) EntryTarget = null,
    /// A ready named target (`focusId`) anywhere in the window, null = none (`ScopeExit.return_focus`).
    find_target: ?*const fn (context: *anyopaque, name: []const u8) ?*Node = null,
    /// A scope entry's placeholder moved `transition_epoch` from `old` to `new` and nothing else
    /// happened: pending work stamped `old` is still current (the placeholder is not an intent).
    restamp: ?*const fn (context: *anyopaque, old: u64, new: u64) void = null,
};

pub const EntryQuery = struct {
    /// The scope's named initial focus (`ScopeEntry.initial_focus`).
    initial: ?[]const u8 = null,
    /// Consider a pending view-model focus request aimed into the scope (entry: yes; the trap
    /// refocus after a released node: no).
    requests: bool = true,
};

/// Answer of `FocusObserver.entry_target`.
pub const EntryTarget = union(enum) {
    /// Focus this node (inside the scope); the entry is done.
    focus: *Node,
    /// The named target is mounted in the scope but not ready (hidden, disabled): hold focus on
    /// the scope's placeholder and wait for it.
    wait,
    /// The named target (or the target of a pending request) is not mounted in the scope yet: it
    /// may still come (rows filled after the open) or never (a stale name). Focus this default now
    /// (null = the first focusable node) as a placeholder and take the target if it shows up
    /// before the user acts.
    later: ?*Node,
    /// No declaration: the first focusable node.
    none,
};

/// How a scope takes focus (`FocusManager.pushScopeWith`).
pub const ScopeEntry = struct {
    /// focusId of the control focused when the scope takes focus (copied; resolved by the
    /// observer inside the scope). null = a declared `autoFocus` inside, else the first focusable.
    initial_focus: ?[]const u8 = null,
    /// Where focus returns when the scope is removed with restore. null = the focus at push.
    default_return: ?*Node = null,
    /// Holds focus while the entry waits for its target (inside the scope, need not be focusable:
    /// a dialog panel). null = the scope node when it is focusable, else the first focusable.
    placeholder: ?*Node = null,
};

/// How a scope gives focus back (`FocusManager.removeScopeWith`).
pub const ScopeExit = struct {
    /// Give focus back (the caller decides, e.g. only while focus is still inside).
    restore: bool,
    /// focusId of the control focus returns to (resolved by the observer in the whole window once
    /// the scope is gone); null or not ready = `ScopeEntry.default_return` / the focus at push.
    /// Only for the active scope: a scope removed from under another keeps that one's trap.
    return_focus: ?[]const u8 = null,
};

/// Focus manager
pub const FocusManager = struct {
    allocator: Allocator,

    /// Node currently holding focus
    current_focus: ?*Node = null,
    current_focus_handle: ?NodeHandle = null,

    // Focus changes are synchronous, but callbacks may start a newer change.
    // Only that newest transition may continue publishing state/events.
    transition_epoch: u64 = 0,
    transition_depth: usize = 0,
    /// Lifetime guard independent of focus nesting (settled callbacks may redirect).
    callback_depth: usize = 0,

    /// Tab order table (focusable node list)
    focus_order: std.ArrayList(*Node),

    /// Dispatcher reference (for dispatching focus/blur bubble events)
    dispatcher: ?*event_dispatcher_mod.EventDispatcher = null,

    /// Accessibility bridge
    a11y_bridge: AccessibilityBridge = .{},

    /// Node registry (for resolving current focus via handle across frames)
    registry: ?*NodeRegistry = null,

    /// Called after blur/focus handlers and the focus handle update have all
    /// settled. Cx uses this hook to reconcile the window-level native
    /// text-input session; widgets must not toggle that session themselves.
    ///
    /// This hook covers only focus changes that go through setFocusWithReason.
    /// The paths that change effective focus *without* dispatching events,
    /// `unregisterFocusableSubtree` + `restoreFocusAfterSubtreeRebuild` during
    /// a runtime-index rebuild, and `unregisterFocusableSilent` during node
    /// teardown, are reconciled by Cx at their own boundary instead. Any new
    /// path that writes `current_focus` directly owes the same reconcile.
    observer: ?FocusObserver = null,
    settled_context: ?*anyopaque = null,
    on_focus_settled: ?*const fn (context: *anyopaque) void = null,

    /// Focus Scope stack (Phase 6: 8->64; full ArrayList migration deferred to Phase 7)
    scope_stack: [SCOPE_STACK_CAP]?*Node = @as([SCOPE_STACK_CAP]?*Node, @splat(null)),
    scope_stack_handles: [SCOPE_STACK_CAP]?NodeHandle = @as([SCOPE_STACK_CAP]?NodeHandle, @splat(null)),
    scope_count: u8 = 0,

    /// Focus memory (per-scope stack saves focus ID before entering)
    scope_memory: [SCOPE_STACK_CAP]?u32 = @as([SCOPE_STACK_CAP]?u32, @splat(null)),
    scope_memory_handles: [SCOPE_STACK_CAP]?NodeHandle = @as([SCOPE_STACK_CAP]?NodeHandle, @splat(null)),

    /// Scoped focus order buffer (Phase 6: 64->512)
    scoped_buf: [SCOPED_BUF_CAP]*Node = undefined,
    /// The pending entry of the active auto-focus scope (it has not settled on its target yet,
    /// see `pushScopeWith`). One at a time: pushing another scope ends it.
    scope_entry: ?PendingEntry = null,
    /// Counts user input (pointer down, key down, wheel; `noteUserInput`): a pending scope entry
    /// ends at the first one, so a target that shows up later never takes focus from under the
    /// user.
    input_epoch: u64 = 0,
    /// Focus lost to a released node while a trap scope was active (`refocusActiveTrapScope`).
    pending_trap_refocus: ?struct { node: ?*Node, handle: ?NodeHandle, epoch: u64 } = null,

    /// Most recent focus change reason (for :focus-visible)
    last_focus_reason: FocusReason = .programmatic,

    input_modality: InputModality = .pointer,
    focus_visible: bool = false,
    visibility_listeners: std.ArrayList(VisibilityListener) = .empty,
    next_visibility_id: u64 = 0,

    const PendingEntry = struct {
        scope_id: u32,
        /// `transition_epoch` at push, or after this entry's own last placeholder.
        epoch: u64,
        input_epoch: u64,
        /// Owned copy of `ScopeEntry.initial_focus`.
        name: ?[]u8,
        /// `ScopeEntry.placeholder` (identity-checked before use).
        placeholder: ?*Node,
        placeholder_handle: ?NodeHandle,
    };

    const VisibilityListener = struct {
        id: u64,
        context: *anyopaque,
        callback: *const fn (*anyopaque) void,
    };

    pub fn subscribeVisibility(self: *FocusManager, context: *anyopaque, callback: *const fn (*anyopaque) void) !u64 {
        const id = std.math.add(u64, self.next_visibility_id, 1) catch return error.OutOfMemory;
        try self.visibility_listeners.append(self.allocator, .{ .id = id, .context = context, .callback = callback });
        self.next_visibility_id = id;
        return id;
    }

    // IDs remain sorted because subscription appends and removal preserves order.
    fn visibilityLowerBound(self: *FocusManager, id: u64) usize {
        var low: usize = 0;
        var high = self.visibility_listeners.items.len;
        while (low < high) {
            const middle = low + (high - low) / 2;
            if (self.visibility_listeners.items[middle].id < id) low = middle + 1 else high = middle;
        }
        return low;
    }

    pub fn unsubscribeVisibility(self: *FocusManager, id: u64) void {
        const index = self.visibilityLowerBound(id);
        if (index < self.visibility_listeners.items.len and self.visibility_listeners.items[index].id == id)
            _ = self.visibility_listeners.orderedRemove(index);
    }

    pub fn hasVisibilitySubscription(self: *FocusManager, id: u64) bool {
        const index = self.visibilityLowerBound(id);
        return index < self.visibility_listeners.items.len and self.visibility_listeners.items[index].id == id;
    }

    fn notifyVisibility(self: *FocusManager) void {
        self.callback_depth += 1;
        defer self.callback_depth -= 1;
        const epoch = self.transition_epoch;
        const last_id = self.next_visibility_id;
        var index: usize = 0;
        while (index < self.visibility_listeners.items.len) {
            // Copy before invoking: callbacks may remove subscriptions or grow the list.
            const listener = self.visibility_listeners.items[index];
            if (listener.id > last_id) break;
            listener.callback(listener.context);
            if (self.transition_epoch != epoch) return;
            if (index < self.visibility_listeners.items.len and self.visibility_listeners.items[index].id == listener.id) {
                index += 1;
            } else {
                // Only removals at/before the cursor require a reseek. Unchanged
                // delivery is linear; callbacks added mid-delivery wait until next time.
                index = self.visibilityLowerBound(listener.id);
                if (index < self.visibility_listeners.items.len and self.visibility_listeners.items[index].id == listener.id) index += 1;
            }
        }
    }

    /// Record input before dispatch: programmatic focus inside a handler inherits it.
    /// User input reached the window (pointer down, key down, wheel): ends a pending scope entry.
    pub fn noteUserInput(self: *FocusManager) void {
        self.input_epoch +%= 1;
    }

    pub fn noteInputModality(self: *FocusManager, modality: InputModality) void {
        self.noteUserInput();
        self.input_modality = modality;
        const visible = modality == .keyboard and self.getFocused() != null;
        if (visible == self.focus_visible) return;
        self.transition_epoch = std.math.add(u64, self.transition_epoch, 1) catch @panic("focus epoch exhausted");
        self.focus_visible = visible;
        self.notifyVisibility();
    }

    pub fn init(allocator: Allocator) FocusManager {
        return .{
            .allocator = allocator,
            .focus_order = .empty,
        };
    }

    pub fn deinit(self: *FocusManager) void {
        self.dropEntry();
        self.visibility_listeners.deinit(self.allocator);
        self.focus_order.deinit(self.allocator);
    }

    pub fn setRegistry(self: *FocusManager, registry: *NodeRegistry) void {
        self.registry = registry;
    }

    fn trackedHandleFor(self: *FocusManager, node: *Node) ?NodeHandle {
        const registry = self.registry orelse return null;
        const generation = registry.trackGeneration(node) catch return registry.handleFor(node);
        return .{ .id = node.id, .generation = generation };
    }

    /// Set focus to given node
    /// Triggers blur (old node) and focus (new node) events
    pub fn setFocus(self: *FocusManager, node: ?*Node) void {
        self.setFocusWithReason(node, .programmatic);
    }

    /// Identity handle taken while `node` is known to be alive. Returns null
    /// only when no identity can be established (no registry, or generation
    /// tracking failed on OOM). Registry-backed transitions fail closed when
    /// no identity can be established; registry-free callers own lifetime.
    fn identityHandleFor(self: *FocusManager, node: *Node) ?NodeHandle {
        const registry = self.registry orelse return null;
        const generation = registry.trackGeneration(node) catch return null;
        return .{ .id = node.id, .generation = generation };
    }

    /// Whether `node`'s memory survived the application callbacks run since
    /// `identity` was taken. Compares identity only (generation + pointer via
    /// `isCurrentIdentity`) and never dereferences `node`: a synchronous
    /// blur/focus handler may have freed it, and freeNode frees immediately
    /// outside tick/reactive depth (noteNodeFreed invalidates the identity).
    /// A registry-backed node with no identity must not cross callbacks.
    /// Registry-free callers retain their nodes for the whole transition.
    fn survivedCallbacks(self: *FocusManager, identity: ?NodeHandle, node: *Node) bool {
        const registry = self.registry orelse return true;
        const h = identity orelse return false;
        return registry.isCurrentIdentity(h, node);
    }

    /// Whether a live node may still become the focus owner. A node claimed
    /// for destruction (freeNode deferred inside a reactive callback / tick)
    /// is kept in memory but already unlinked from the tree; focusing it
    /// would publish a pointer that dies at the next drain.
    fn canReceiveFocus(self: *FocusManager, identity: ?NodeHandle, node: *Node) bool {
        if (!self.survivedCallbacks(identity, node)) return false;
        return !node.freeing and node.pending_free_cx == null;
    }

    /// Deliver once. An ignored event was still delivered; only an absent
    /// dispatcher/registry entry requires the mount-time direct fallback.
    fn deliverFocusEvent(self: *FocusManager, node: *Node, event: Event) void {
        if (self.dispatcher) |dispatcher| {
            const reachable = if (dispatcher.registry) |registry|
                registry.resolve(registry.handleFor(node), null) == node
            else
                true;
            if (reachable) {
                _ = dispatcher.dispatch(event, node);
                return;
            }
        }
        if (node.behavior.events.on_event) |handler| {
            _ = handler(event, node.behavior.events.event_context);
        }
    }

    fn finishFocusTransition(self: *FocusManager) void {
        self.transition_depth -= 1;
        if (self.transition_depth != 0) return;
        // Settled callbacks can start another fully settled transition. Keep a
        // separate lifetime guard so this does not suppress its notification.
        self.callback_depth += 1;
        defer self.callback_depth -= 1;
        // Publish only the settled owner, never an outer transition's stale
        // local target. The settled hook may itself request a new transition.
        self.notifyVisibility();
        self.a11y_bridge.notifyFocusChange(self.getFocused());
        if (self.on_focus_settled) |callback| {
            if (self.settled_context) |context| callback(context);
        }
    }

    /// Synchronous, latest-request-wins focus transitions. Withdraw the old
    /// owner before blur callbacks, so a reentrant request cannot blur it twice.
    /// After each callback boundary, a superseded transition stops immediately.
    /// Identity checks independently protect targets destroyed by callbacks.
    /// Without a registry the caller must retain nodes across callbacks.
    pub fn setFocusWithReason(self: *FocusManager, node: ?*Node, reason: FocusReason) void {
        self.setFocusWithVisibility(node, reason, .inherit);
    }

    pub fn setFocusWithVisibility(self: *FocusManager, node: ?*Node, reason: FocusReason, visibility: FocusVisibility) void {
        // Capture the inherited policy before callbacks can change it.
        switch (reason) {
            .click => self.input_modality = .pointer,
            .tab => self.input_modality = .keyboard,
            .programmatic => {},
        }
        const visible = node != null and switch (visibility) {
            .inherit => self.input_modality == .keyboard,
            .show => true,
            .hide => false,
        };
        const old_node = self.getFocused();
        if (old_node == node) {
            self.transition_epoch = std.math.add(u64, self.transition_epoch, 1) catch @panic("focus epoch exhausted");
            self.last_focus_reason = reason;
            self.focus_visible = visible;
            self.notifyVisibility();
            return;
        }

        const old_id: ?u32 = if (old_node) |old| old.id else null;
        const new_id: ?u32 = if (node) |new| new.id else null;
        const old_identity = if (old_node) |old| self.identityHandleFor(old) else null;
        const new_identity = if (node) |new| self.identityHandleFor(new) else null;
        // Never downgrade a registry-backed transition to unchecked pointers
        // if identity allocation fails. Preserve the current owner instead.
        if (node != null and self.registry != null and new_identity == null) return;

        // focus-within: ancestors (and the node itself) that focus leaves / enters, taken from
        // the tree before any callback can change it.
        var leaving: WithinList = .{};
        var entering: WithinList = .{};
        if (old_node) |old| self.collectWithin(&leaving, old, node, .blur);
        if (node) |new| self.collectWithin(&entering, new, old_node, .focus);

        self.transition_epoch = std.math.add(u64, self.transition_epoch, 1) catch @panic("focus epoch exhausted");
        const epoch = self.transition_epoch;
        self.transition_depth += 1;
        defer self.finishFocusTransition();

        self.current_focus = null;
        self.current_focus_handle = null;
        self.last_focus_reason = reason;
        self.focus_visible = visible;
        if (old_node) |old| {
            old.markRenderDirty();
            if (old.behavior.events.on_blur) |handler| handler.invoke();
            if (self.transition_epoch != epoch) return;
            if (self.survivedCallbacks(old_identity, old)) {
                self.deliverFocusEvent(old, .{ .blur = .{
                    .related_node_id = new_id,
                    .reason = reason,
                } });
                if (self.transition_epoch != epoch) return;
            }
        }
        if (!self.invokeWithin(&leaving, .blur, epoch)) return;

        if (node == null) if (self.observer) |o| o.focused(o.context, null);
        if (node) |new| {
            if (!self.canReceiveFocus(new_identity, new)) return;
            self.current_focus = new;
            self.current_focus_handle = new_identity;
            if (self.observer) |o| o.focused(o.context, new);
            new.markRenderDirty();
            if (new.behavior.events.on_focus) |handler| handler.invoke();
            if (self.transition_epoch != epoch) return;
            if (self.canReceiveFocus(new_identity, new) and self.getFocused() == new) {
                self.deliverFocusEvent(new, .{ .focus = .{
                    .related_node_id = old_id,
                    .reason = reason,
                } });
                if (self.transition_epoch != epoch) return;
                _ = self.invokeWithin(&entering, .focus, epoch);
            }
        }
    }

    const WithinKind = enum { focus, blur };
    /// Deeper ancestors than this are not notified (no real tree nests that many listeners).
    const max_within = 32;
    const WithinList = struct {
        nodes: [max_within]*Node = undefined,
        identities: [max_within]?NodeHandle = undefined,
        len: usize = 0,
    };

    fn withinHandler(node: *const Node, kind: WithinKind) ?core.HandlerRef {
        return switch (kind) {
            .focus => node.behavior.events.on_focus_within,
            .blur => node.behavior.events.on_blur_within,
        };
    }

    /// `from` and its ancestors with a focus-within handler of `kind` that do not also contain
    /// `other` (focus moving inside a subtree neither leaves nor enters it), innermost first.
    fn collectWithin(self: *FocusManager, list: *WithinList, from: *Node, other: ?*Node, kind: WithinKind) void {
        var cur: ?*Node = from;
        while (cur) |n| : (cur = n.parent) {
            if (withinHandler(n, kind) == null) continue;
            if (other) |o| if (isAncestorOrSelf(n, o)) break;
            if (list.len == max_within) return;
            list.nodes[list.len] = n;
            list.identities[list.len] = self.identityHandleFor(n);
            list.len += 1;
        }
    }

    fn isAncestorOrSelf(ancestor: *const Node, node: *const Node) bool {
        var cur: ?*const Node = node;
        while (cur) |n| : (cur = n.parent) if (n == ancestor) return true;
        return false;
    }

    /// Run the collected handlers innermost first; a node freed by an earlier callback is
    /// skipped, a superseding transition stops the rest (returns false).
    fn invokeWithin(self: *FocusManager, list: *const WithinList, kind: WithinKind, epoch: u64) bool {
        for (list.nodes[0..list.len], list.identities[0..list.len]) |n, identity| {
            if (!self.survivedCallbacks(identity, n)) continue;
            if (self.registry != null and identity == null) continue;
            if (withinHandler(n, kind)) |handler| handler.invoke();
            if (self.transition_epoch != epoch) return false;
        }
        return true;
    }

    /// Clear focus
    pub fn clearFocus(self: *FocusManager) void {
        self.setFocusWithReason(null, .programmatic);
    }

    /// Focus holder's callback context about to destroy (component scope dispose, node may
    /// still be on tree): remove focus without calling blur handler / dispatching blur event,
    /// as those handlers read state being released, and their dependent subscopes/signals may
    /// already be freed. a11y and native input session still sync. Node stays in focus_order.
    pub fn abandonFocus(self: *FocusManager, node: *Node) void {
        const owns = self.current_focus == node or
            (if (self.current_focus_handle) |h| h.id == node.id else false);
        if (!owns) return;
        if (self.observer) |o| o.lost(o.context, node, true);
        self.current_focus = null;
        self.current_focus_handle = null;
        self.refocusActiveTrapScope();
        self.a11y_bridge.notifyFocusChange(null);
        if (self.on_focus_settled) |callback| {
            if (self.settled_context) |context| callback(context);
        }
    }

    /// Register focusable node
    pub fn registerFocusable(self: *FocusManager, node: *Node) !void {
        // Avoid duplicate registration
        for (self.focus_order.items) |n| {
            if (n == node) return;
        }
        try self.focus_order.append(self.allocator, node);
    }

    pub fn clearFocusOrder(self: *FocusManager) void {
        self.focus_order.clearRetainingCapacity();
    }

    pub fn appendFocusableUnsorted(self: *FocusManager, node: *Node) !void {
        const is_focusable = node.behavior.interaction.focusable or node.behavior.interaction.tab_index != null;
        const excluded_from_tab = if (node.behavior.interaction.tab_index) |ti| ti < 0 else false;
        if (is_focusable and !excluded_from_tab) {
            try self.focus_order.append(self.allocator, node);
        }
    }

    pub fn finalizeFocusOrder(self: *FocusManager) void {
        if (self.focus_order.items.len <= 1) return;
        // Sort key: tab_index (positive ascending first), then **actual tree order**. Stable
        // sort alone preserves insertion order but not tree order: incremental subtree rebuild
        // appends re-laid nodes to the end, insertion_order != tree_order, Tab order scrambles
        // (focusable nodes in subtree moved to end).
        std.sort.block(*Node, self.focus_order.items, {}, struct {
            fn lessThan(_: void, a: *Node, b: *Node) bool {
                const a_idx = effectiveTabOrder(a);
                const b_idx = effectiveTabOrder(b);
                if (a_idx != b_idx) return a_idx < b_idx;
                return compareTreeOrder(a, b) == .lt;
            }
        }.lessThan);
    }

    /// The focused node went away (released, its subtree removed, or its owner abandoned it) while a
    /// trap scope is active (an open Modal / Popover with `trap_focus`): focus goes back into that
    /// scope at the next settle (`settleTrapRefocus`), instead of leaving the
    /// open panel unfocused. A panel that rebuilds the row holding focus keeps focus inside.
    pub fn refocusActiveTrapScope(self: *FocusManager) void {
        if (self.scope_count == 0) return;
        const index = self.scope_count - 1;
        const handle = self.scope_stack_handles[index];
        const node = self.scope_stack[index];
        const scope_node: ?*Node = if (self.registry) |registry| (if (handle) |h| registry.resolve(h, null) else null) else node;
        const scope = scope_node orelse return;
        const cfg = scope.behavior.interaction.focus_scope orelse return;
        if (!cfg.trap) return;
        self.pending_trap_refocus = .{ .node = node, .handle = handle, .epoch = self.transition_epoch };
    }

    /// Settle `refocusActiveTrapScope` once per frame, after named focus restoration
    /// (`FocusTargets.settle`) had its turn: any focus transition since the loss, focus already
    /// somewhere, or a different active scope drops it.
    pub fn settleTrapRefocus(self: *FocusManager) void {
        const pending = self.pending_trap_refocus orelse return;
        self.pending_trap_refocus = null;
        if (pending.epoch != self.transition_epoch or self.getFocused() != null) return;
        const active = self.activeScope() orelse return;
        const same = if (pending.handle) |h| h.id == active.id else pending.node == active;
        if (!same) return;
        _ = self.focusScopeNow(active);
    }

    /// Silent removal (node release path): no blur handler, callback context may be gone
    /// with scope, invoke is UAF. Just unlink + clear current_focus.
    pub fn unregisterFocusableSilent(self: *FocusManager, node: *Node) void {
        // Pointer/handle comparison only, never call getFocused(): during teardown recursive
        // free, current_focus may point to freed sibling, getFocused cached fallback dereferences
        // it -> UAF/segfault (real app proves it).
        if (self.current_focus == node) {
            if (self.observer) |o| o.lost(o.context, node, false);
            self.current_focus = null;
            self.current_focus_handle = null;
            self.refocusActiveTrapScope();
        } else if (self.current_focus_handle) |h| {
            if (h.id == node.id) {
                if (self.observer) |o| o.lost(o.context, node, false);
                self.current_focus = null;
                self.current_focus_handle = null;
                self.refocusActiveTrapScope();
            }
        }
        for (self.focus_order.items, 0..) |n, i| {
            if (n == node) {
                _ = self.focus_order.orderedRemove(i);
                return;
            }
        }
    }

    /// Recover focus after an incremental runtime-index rebuild (core.rebuildDirtyRuntimeSubtrees
    /// only): the rebuild only relinks registry/focus_order; node identity is unchanged (same
    /// pointer, same id, re-registered). No blur/focus events are sent since focus never left
    /// the node; setFocus would send a false blur/focus pair, prematurely shutting the native
    /// input gate on input components.
    pub fn restoreFocusAfterSubtreeRebuild(self: *FocusManager, node: *Node) void {
        self.current_focus = node;
        self.current_focus_handle = self.trackedHandleFor(node);
    }

    /// Remove focusable node
    pub fn unregisterFocusable(self: *FocusManager, node: *Node) void {
        for (self.focus_order.items, 0..) |n, i| {
            if (n == node) {
                // Do not retain a mutable-list index across application code.
                // A blur callback may unregister again, destroy this node, or
                // intentionally re-register it for a new interaction lifetime.
                _ = self.focus_order.orderedRemove(i);
                if (self.getFocused() == node) {
                    self.setFocusWithReason(null, .programmatic);
                }
                return;
            }
        }
    }

    pub fn unregisterFocusableSubtree(self: *FocusManager, root: *Node) void {
        var write_idx: usize = 0;
        var removed_focused = false;
        const focused = self.getFocused();
        for (self.focus_order.items) |node| {
            if (node.isDescendantOf(root)) {
                if (focused == node) removed_focused = true;
                continue;
            }
            self.focus_order.items[write_idx] = node;
            write_idx += 1;
        }
        self.focus_order.items.len = write_idx;
        if (removed_focused) {
            self.current_focus = null;
            self.current_focus_handle = null;
            self.refocusActiveTrapScope();
        }
    }

    /// Move focus to next focusable node (Tab)
    pub fn focusNext(self: *FocusManager) void {
        self.focusStep(.forward);
    }

    /// Move focus to previous focusable node (Shift+Tab)
    pub fn focusPrev(self: *FocusManager) void {
        self.focusStep(.backward);
    }

    /// Tab / Shift+Tab: from current focus along order forward / back, skipping nodes in
    /// display:none subtrees and inside closed dialogs (`keyboardReachable`; focus_order is
    /// collected on struct change, display toggles and scope pushes do not recollect, so both
    /// are checked during traversal).
    fn focusStep(self: *FocusManager, dir: enum { forward, backward }) void {
        const order = self.scopedFocusOrder();
        if (order.len == 0) return;

        var start: usize = if (dir == .forward) order.len - 1 else 0; // No current focus: start from first / end
        if (self.getFocused()) |current| {
            for (order, 0..) |n, i| {
                if (n == current) {
                    start = i;
                    break;
                }
            }
        }
        var i = start;
        for (0..order.len) |_| {
            i = if (dir == .forward) (i + 1) % order.len else (if (i == 0) order.len - 1 else i - 1);
            if (self.keyboardReachable(order[i])) {
                self.setFocusWithReason(order[i], .tab);
                return;
            }
        }
    }

    /// Get current focused node
    pub fn getFocused(self: *FocusManager) ?*Node {
        if (self.registry) |registry| {
            if (registry.resolve(self.current_focus_handle, null)) |resolved| {
                self.current_focus = resolved;
                return resolved;
            }
            if (self.current_focus_handle != null) {
                if (self.current_focus) |cached| {
                    if (registry.isCurrentIdentity(self.current_focus_handle.?, cached)) {
                        return cached;
                    }
                }
                self.current_focus = null;
                self.current_focus_handle = null;
                self.refocusActiveTrapScope();
                return null;
            }
        }
        return self.current_focus;
    }

    /// Check whether node owns focus
    pub fn isFocused(self: *FocusManager, node: *Node) bool {
        return self.getFocused() == node;
    }

    /// Auto-collect focusable nodes from the node tree, sorted by tab_index.
    /// Sort rules (align HTML tabindex semantics):
    /// 1. tab_index > 0 nodes first, ascending tab_index, ties in tree order
    /// 2. tab_index == 0 or null (focusable=true) next, tree order
    /// 3. tab_index == -1 not in focus_order (focus via click/setFocus only)
    pub fn collectFocusableNodes(self: *FocusManager, root: *Node) !void {
        self.clearFocusOrder();
        try self.collectRecursive(root);
        self.finalizeFocusOrder();
    }

    pub fn replaceDefaultOrderSubtree(self: *FocusManager, root: *Node) !void {
        var first_removed_index: ?usize = null;
        var write_idx: usize = 0;

        for (self.focus_order.items, 0..) |node, i| {
            if (node.isDescendantOf(root)) {
                if (first_removed_index == null) first_removed_index = i;
                continue;
            }
            self.focus_order.items[write_idx] = node;
            write_idx += 1;
        }
        self.focus_order.items.len = write_idx;

        var collected = @as(std.ArrayList(*Node), .empty);
        defer collected.deinit(self.allocator);
        try collectDefaultOrderRecursive(root, &collected, self.allocator);

        const focused = self.getFocused();
        if (focused) |node| {
            if (node.isDescendantOf(root) and !sliceContainsNode(collected.items, node)) {
                self.setFocusWithReason(null, .programmatic);
            }
        }

        if (collected.items.len == 0) return;

        const insert_idx = first_removed_index orelse self.findDefaultInsertIndex(root);
        try self.focus_order.ensureUnusedCapacity(self.allocator, collected.items.len);
        const old_len = self.focus_order.items.len;
        self.focus_order.items.len = old_len + collected.items.len;
        std.mem.copyBackwards(
            *Node,
            self.focus_order.items[insert_idx + collected.items.len .. self.focus_order.items.len],
            self.focus_order.items[insert_idx..old_len],
        );
        @memcpy(self.focus_order.items[insert_idx .. insert_idx + collected.items.len], collected.items);
    }

    /// Compute effective sort priority for node
    /// tab_index > 0 -> direct use (1, 2, 3...)
    /// tab_index == 0 or null (focusable=true) -> large number (keep tree order later)
    fn effectiveTabOrder(node: *Node) i64 {
        if (node.behavior.interaction.tab_index) |ti| {
            if (ti > 0) return ti;
            // ti == 0 sorts after positive per tree order
            return std.math.maxInt(i32);
        }
        // null (focusable=true) equals 0, sorts per tree order
        return std.math.maxInt(i32);
    }

    fn collectRecursive(self: *FocusManager, node: *Node) !void {
        try self.appendFocusableUnsorted(node);

        for (node.children.items) |child| {
            try self.collectRecursive(child);
        }
    }

    fn findDefaultInsertIndex(self: *FocusManager, root: *Node) usize {
        var idx: usize = 0;
        while (idx < self.focus_order.items.len) : (idx += 1) {
            const node = self.focus_order.items[idx];
            if (effectiveTabOrder(node) != std.math.maxInt(i32)) continue;
            if (compareTreeOrder(root, node) == .lt) return idx;
        }
        return self.focus_order.items.len;
    }

    // ---- Focus Scope ----

    /// Push a focus scope with default entry (see `pushScopeWith`).
    pub fn pushScope(self: *FocusManager, scope_node: *Node) void {
        self.pushScopeWith(scope_node, .{});
    }

    /// Push a focus scope (a Modal / Sheet / Popover opens): remember where focus returns
    /// (`entry.default_return`, else the focus now) and, for an `auto_focus` scope, move focus in.
    ///
    /// Entry: focus already inside the scope stays (the opener put it there). Else the observer
    /// (`entry_target`) names the target: a pending view-model request aimed into the scope, the
    /// named `entry.initial_focus`, a declared `autoFocus`; else the first focusable node. Until a
    /// named target is ready, the entry stays pending: focus is held inside the scope (on
    /// `entry.placeholder`, or a default control, see `EntryTarget`) and moves to the target in the
    /// settle where it becomes ready (`settleScopeEntry`). Holding is a placeholder, not an intent:
    /// it supersedes neither the entry nor other pending declarative focus (`restamp`). The entry
    /// ends at its target, at any other focus transition, at user input (`input_epoch`), or when
    /// the scope stops being the active one.
    pub fn pushScopeWith(self: *FocusManager, scope_node: *Node, entry: ScopeEntry) void {
        if (self.scope_count >= self.scope_stack.len) return;
        const slot = self.scope_count;

        const restore = entry.default_return orelse self.getFocused();
        self.scope_memory[slot] = if (restore) |n| n.id else null;
        self.scope_memory_handles[slot] = if (entry.default_return) |n| self.trackedHandleFor(n) else self.current_focus_handle;

        self.scope_stack[slot] = if (self.registry == null) scope_node else null;
        self.scope_stack_handles[slot] = self.trackedHandleFor(scope_node);
        self.scope_count += 1;
        // A scope pushed over a pending entry ends it.
        self.dropEntry();

        const cfg = scope_node.behavior.interaction.focus_scope orelse return;
        if (!cfg.auto_focus) return;
        if (self.getFocused()) |focused| if (focused == scope_node or focused.isDescendantOf(scope_node)) return;
        const name: ?[]u8 = if (entry.initial_focus) |n| (self.allocator.dupe(u8, n) catch null) else null;
        self.scope_entry = .{
            .scope_id = scope_node.id,
            .epoch = self.transition_epoch,
            .input_epoch = self.input_epoch,
            .name = name,
            .placeholder = entry.placeholder,
            .placeholder_handle = if (entry.placeholder) |n| self.trackedHandleFor(n) else null,
        };
        self.resolveEntry();
    }

    fn dropEntry(self: *FocusManager) void {
        if (self.scope_entry) |e| if (e.name) |n| self.allocator.free(n);
        self.scope_entry = null;
    }

    /// The active scope of a live pending entry, else null (dropping a stale entry). A scope just
    /// mounted may not resolve yet (not in the node index until the next rebuild): the entry
    /// stays, the next settle retries.
    fn liveEntryScope(self: *FocusManager) ?*Node {
        const e = self.scope_entry orelse return null;
        const top_id: ?u32 = if (self.scope_count == 0) null else if (self.scope_stack_handles[self.scope_count - 1]) |h| h.id else if (self.scope_stack[self.scope_count - 1]) |n| n.id else null;
        if (e.epoch != self.transition_epoch or e.input_epoch != self.input_epoch or top_id == null or top_id.? != e.scope_id) {
            self.dropEntry();
            return null;
        }
        return self.activeScope();
    }

    /// The active scope while its entry is pending (declarative focus inside it waits for the
    /// entry: `FocusTargets` leaves the `autoFocus` targets inside to `entry_target`).
    pub fn pendingEntryScope(self: *FocusManager) ?*Node {
        return self.liveEntryScope();
    }

    /// The scope's named initial focus changed while its entry is pending (the name depends on
    /// data that arrived after the open): wait for the new name instead.
    pub fn updateScopeEntry(self: *FocusManager, scope_node: *Node, initial_focus: ?[]const u8) void {
        const scope = self.liveEntryScope() orelse return;
        if (scope != scope_node) return;
        const e = &self.scope_entry.?;
        if (e.name) |old| {
            if (initial_focus) |n| if (std.mem.eql(u8, old, n)) return;
            self.allocator.free(old);
        } else if (initial_focus == null) return;
        e.name = if (initial_focus) |n| (self.allocator.dupe(u8, n) catch null) else null;
        self.resolveEntry();
    }

    /// Settle the active scope's pending entry: after the window's indexes are rebuilt (a target
    /// mounted in this frame is focused in this frame), after the before-render tick and at the
    /// start of each rendered frame (a target shown or enabled without an order change).
    pub fn settleScopeEntry(self: *FocusManager) void {
        if (self.scope_entry == null) return;
        self.resolveEntry();
    }

    /// One attempt at the pending entry.
    fn resolveEntry(self: *FocusManager) void {
        const scope_node = self.liveEntryScope() orelse return;
        const e = self.scope_entry.?;
        const pick: EntryTarget = if (self.observer) |o| (if (o.entry_target) |resolve| resolve(o.context, scope_node, .{ .initial = e.name }) else .none) else .none;
        // The observer may have run callbacks: re-check before acting.
        if (self.liveEntryScope() != scope_node) return;
        switch (pick) {
            .focus => |target| if (target == scope_node or target.isDescendantOf(scope_node)) {
                self.dropEntry();
                self.setFocus(target);
                return;
            },
            .none => if (self.firstReachableIn(scope_node)) |target| {
                self.dropEntry();
                self.setFocus(target);
                return;
            },
            .wait, .later => {},
        }
        const holder = self.entryHolder(scope_node, e);
        const hold: ?*Node = switch (pick) {
            .later => |default| (if (default) |d| (if (d == scope_node or d.isDescendantOf(scope_node)) d else null) else null) orelse self.firstReachableIn(scope_node) orelse holder,
            else => holder orelse self.firstReachableIn(scope_node),
        };
        if (hold) |node| if (self.getFocused() != node) self.placeholderFocus(node);
    }

    /// Where a waiting entry holds focus: `ScopeEntry.placeholder` while alive and reachable, else
    /// the scope node when it can take focus.
    fn entryHolder(self: *FocusManager, scope_node: *Node, e: PendingEntry) ?*Node {
        if (e.placeholder) |p| {
            const alive = if (self.registry) |r| (if (e.placeholder_handle) |h| r.isCurrentIdentity(h, p) else false) else true;
            if (alive and (p == scope_node or p.isDescendantOf(scope_node)) and self.keyboardReachable(p)) return p;
            return null;
        }
        const i = scope_node.behavior.interaction;
        if ((i.focusable or i.tab_index != null) and self.keyboardReachable(scope_node)) return scope_node;
        return null;
    }

    fn firstReachableIn(self: *FocusManager, scope_node: *Node) ?*Node {
        for (self.scopedFocusOrder()) |n| {
            if (n.isDescendantOf(scope_node) and self.keyboardReachable(n)) return n;
        }
        return null;
    }

    /// Hold focus on `node` for the pending entry: no focus ring, and when nothing but this
    /// transition happened, every pending item stamped with the previous epoch is restamped (the
    /// entry itself, the trap refocus, the observer's requests / autoFocus / restore).
    fn placeholderFocus(self: *FocusManager, node: *Node) void {
        const before = self.transition_epoch;
        self.setFocusWithVisibility(node, .programmatic, .hide);
        const after = self.transition_epoch;
        const e = &(self.scope_entry orelse return);
        if (after != before + 1 or e.epoch != before) {
            self.dropEntry();
            return;
        }
        e.epoch = after;
        if (self.pending_trap_refocus) |*p| if (p.epoch == before) {
            p.epoch = after;
        };
        if (self.observer) |o| if (o.restamp) |restamp| restamp(o.context, before, after);
    }

    /// Focus back into the active trap scope after its focused node went away
    /// (`settleTrapRefocus`): a declared `autoFocus` inside, else the first focusable node. No
    /// requests, no named entry, no placeholder.
    fn focusScopeNow(self: *FocusManager, scope_node: *Node) bool {
        if (self.observer) |o| if (o.entry_target) |resolve| switch (resolve(o.context, scope_node, .{ .requests = false })) {
            .focus => |target| if (target == scope_node or target.isDescendantOf(scope_node)) {
                self.setFocus(target);
                return true;
            },
            .wait, .later, .none => {},
        };
        const target = self.firstReachableIn(scope_node) orelse return false;
        self.setFocus(target);
        return true;
    }

    /// Tab traversal / scope auto-focus may land on `node`: displayed, and not inside a trap
    /// scope that is not on the scope stack (a closed Modal / Sheet keeps its content mounted;
    /// the content is inert until the dialog's scope is pushed again), and not inside an `inert`
    /// subtree (`NodeInteraction.inert`).
    pub fn keyboardReachable(self: *FocusManager, node: *const Node) bool {
        if (!node.isDisplayedInTree()) return false;
        var cur: ?*const Node = node;
        while (cur) |n| : (cur = n.parent) {
            if (n.behavior.interaction.inert) return false;
            const cfg = n.behavior.interaction.focus_scope orelse continue;
            if (cfg.trap and !self.scopeOnStack(n)) return false;
        }
        return true;
    }

    fn scopeOnStack(self: *const FocusManager, node: *const Node) bool {
        for (0..self.scope_count) |i| {
            if (self.scope_stack_handles[i]) |h| {
                if (h.id == node.id) return true;
            } else if (self.scope_stack[i] == node) return true;
        }
        return false;
    }

    /// Pop the active scope and restore the focus it remembered.
    pub fn popScope(self: *FocusManager) void {
        if (self.scope_count == 0) return;
        self.popScopeTo(null);
    }

    /// Pop the active scope; focus goes to the named target `return_focus` when it is ready once
    /// the scope is gone, else to the remembered focus, else nowhere.
    fn popScopeTo(self: *FocusManager, return_focus: ?[]const u8) void {
        self.scope_count -= 1;
        const slot = self.scope_count;
        self.scope_stack[slot] = null;
        self.scope_stack_handles[slot] = null;
        self.dropEntry();
        const saved_handle = self.scope_memory_handles[slot];
        const saved_id = self.scope_memory[slot];
        self.scope_memory_handles[slot] = null;
        self.scope_memory[slot] = null;
        // Looked up after the pop: this scope's trap no longer confines the target.
        if (self.namedTarget(return_focus)) |node| {
            self.setFocus(node);
            return;
        }

        // Restore remembered focus
        if (saved_handle) |handle| {
            if (self.registry) |registry| {
                if (registry.resolve(handle, null)) |saved_node| {
                    self.setFocus(saved_node);
                    return;
                }
            }
        } else if (saved_id) |id| {
            for (self.focus_order.items) |node| {
                if (node.id == id) {
                    self.setFocus(node);
                    return;
                }
            }
        }
        // Saved node gone, clear focus
        self.clearFocus();
    }

    /// Remove a particular overlay's scope (see `removeScopeWith`).
    pub fn removeScope(self: *FocusManager, node_id: u32, restore: bool) void {
        self.removeScopeWith(node_id, .{ .restore = restore });
    }

    /// Remove a particular overlay's scope. An ancestor may close while an independently portaled
    /// child still owns focus. With `exit.restore`, a named `exit.return_focus` that is ready once
    /// the scope is gone takes focus; otherwise the active scope gives focus back to what it
    /// remembered (a scope below the active one hands its memory to the scope above it).
    pub fn removeScopeWith(self: *FocusManager, node_id: u32, exit: ScopeExit) void {
        var i: usize = 0;
        while (i < self.scope_count) : (i += 1) {
            const id = if (self.scope_stack_handles[i]) |handle| handle.id else if (self.scope_stack[i]) |node| node.id else continue;
            if (id == node_id) break;
        }
        if (i == self.scope_count) return;
        const top = i + 1 == self.scope_count;
        if (top and exit.restore) {
            self.popScopeTo(exit.return_focus);
            return;
        }

        const end = self.scope_count;
        if (i + 1 < end) {
            // Redirect a nested scope's remembered focus if it points into
            // the removed scope. Keep a live, independent restore target.
            const registry = self.registry;
            const removed = if (registry) |r| r.resolve(self.scope_stack_handles[i], null) else self.scope_stack[i];
            const next_restore = if (registry) |r| r.resolve(self.scope_memory_handles[i + 1], null) else null;
            if (next_restore == null or (removed != null and next_restore.?.isDescendantOf(removed.?))) {
                self.scope_memory[i + 1] = if (exit.restore) self.scope_memory[i] else null;
                self.scope_memory_handles[i + 1] = if (exit.restore) self.scope_memory_handles[i] else null;
            }
            @memmove(self.scope_stack[i .. end - 1], self.scope_stack[i + 1 .. end]);
            @memmove(self.scope_stack_handles[i .. end - 1], self.scope_stack_handles[i + 1 .. end]);
            @memmove(self.scope_memory[i .. end - 1], self.scope_memory[i + 1 .. end]);
            @memmove(self.scope_memory_handles[i .. end - 1], self.scope_memory_handles[i + 1 .. end]);
        } else self.dropEntry();
        self.scope_count -= 1;
        self.scope_stack[end - 1] = null;
        self.scope_stack_handles[end - 1] = null;
        self.scope_memory[end - 1] = null;
        self.scope_memory_handles[end - 1] = null;
    }

    fn namedTarget(self: *FocusManager, name: ?[]const u8) ?*Node {
        const n = name orelse return null;
        const o = self.observer orelse return null;
        const find = o.find_target orelse return null;
        return find(o.context, n);
    }

    /// Forget every scope (Cx teardown / reset): no restore, entries freed.
    pub fn resetScopes(self: *FocusManager) void {
        self.dropEntry();
        self.scope_count = 0;
        self.scope_stack = @as([SCOPE_STACK_CAP]?*Node, @splat(null));
        self.scope_stack_handles = @as([SCOPE_STACK_CAP]?NodeHandle, @splat(null));
        self.scope_memory = @as([SCOPE_STACK_CAP]?u32, @splat(null));
        self.scope_memory_handles = @as([SCOPE_STACK_CAP]?NodeHandle, @splat(null));
        self.pending_trap_refocus = null;
    }

    /// Get current active scope node
    pub fn activeScope(self: *FocusManager) ?*Node {
        if (self.scope_count == 0) return null;
        if (self.registry) |registry| {
            if (registry.resolve(self.scope_stack_handles[self.scope_count - 1], null)) |resolved| {
                self.scope_stack[self.scope_count - 1] = resolved;
                return resolved;
            }
            // Registry exists but resolution fails = scope node freed; cached raw pointer dangling,
            // cannot fall back to use it (Tab would dereference freed node).
            return null;
        }
        return self.scope_stack[self.scope_count - 1];
    }

    /// Get focus order within current scope
    /// If trap scope exists, return only focusable nodes within scope
    pub fn scopedFocusOrder(self: *FocusManager) []*Node {
        const scope = self.activeScope() orelse return self.focus_order.items;

        // Check whether scope is trap
        const is_trap = if (scope.behavior.interaction.focus_scope) |cfg| cfg.trap else false;
        if (!is_trap) return self.focus_order.items;

        // Filter nodes within scope
        var count: usize = 0;
        for (self.focus_order.items) |node| {
            if (count >= self.scoped_buf.len) break;
            if (node.isDescendantOf(scope)) {
                self.scoped_buf[count] = node;
                count += 1;
            }
        }
        return self.scoped_buf[0..count];
    }
};

fn collectDefaultOrderRecursive(node: *Node, out: *std.ArrayList(*Node), allocator: Allocator) !void {
    const is_focusable = node.behavior.interaction.focusable or node.behavior.interaction.tab_index != null;
    const excluded_from_tab = if (node.behavior.interaction.tab_index) |ti| ti < 0 else false;
    const positive_tab_index = if (node.behavior.interaction.tab_index) |ti| ti > 0 else false;
    if (is_focusable and !excluded_from_tab and !positive_tab_index) {
        try out.append(allocator, node);
    }

    for (node.children.items) |child| {
        try collectDefaultOrderRecursive(child, out, allocator);
    }
}

fn sliceContainsNode(nodes: []const *Node, target: *Node) bool {
    for (nodes) |node| {
        if (node == target) return true;
    }
    return false;
}

fn compareTreeOrder(a: *Node, b: *Node) std.math.Order {
    if (a == b) return .eq;

    var a_buf: [128]*Node = undefined;
    var b_buf: [128]*Node = undefined;
    const a_path = buildPathToRoot(a, a_buf[0..]);
    const b_path = buildPathToRoot(b, b_buf[0..]);

    var common: usize = 0;
    while (common < a_path.len and common < b_path.len and a_path[common] == b_path[common]) {
        common += 1;
    }

    // Not in same tree (portal floating layer hangs elsewhere): cannot compare, stable sort
    // keeps original order. Without this, common == 0 reads a_path[-1].
    if (common == 0) return .eq;
    if (common == a_path.len) return .lt;
    if (common == b_path.len) return .gt;

    const parent = a_path[common - 1];
    const a_child = a_path[common];
    const b_child = b_path[common];

    for (parent.children.items) |child| {
        if (child == a_child) return .lt;
        if (child == b_child) return .gt;
    }

    return .eq;
}

fn buildPathToRoot(node: *Node, buf: []*Node) []*Node {
    var count: usize = 0;
    var current: ?*Node = node;
    while (current != null and count < buf.len) : (current = current.?.parent) {
        buf[count] = current.?;
        count += 1;
    }
    // Guard against silent truncation; 128 levels is UI tree extreme (DOM hundreds is
    // pathological), but silent truncate breaks compareTreeOrder alignment. Debug build explicit
    // panic, release build downgrades return truncated path (preserve v0.5 behavior, avoid
    // production crash).
    if (current != null) {
        if (std.debug.runtime_safety) {
            std.debug.panic("focus.zig: buildPathToRoot exceeded buf.len={d}, tree too deep", .{buf.len});
        }
    }
    std.mem.reverse(*Node, buf[0..count]);
    return buf[0..count];
}

// Accessibility bridge (was src/ui/accessibility.zig, merged here in v0.5-P6)
// FocusManager now holds a11y_bridge field; bridge definition inlined to remove separate file.
// Full a11y_tree projection + nsaccessibility_router path in src/ui/a11y/; this bridge is
// a single-point notify compatibility layer (macOS NSAccessibility / Linux AT-SPI / Windows UIA
// single call entry).

pub const AccessibilityBridge = struct {
    enabled: bool = false,
    /// Cx's retained accessibility tree owns precise element-level focus
    /// notifications. Standalone users of this compatibility bridge keep the
    /// historical automatic snapshot behavior.
    automatic_focus_notifications: bool = true,
    sdk: ?*system_sdk.SystemSdk = null,
    window_id: system_sdk.events.WindowId = 1,

    pub fn attachSystemSdk(self: *AccessibilityBridge, sdk: ?*system_sdk.SystemSdk, window_id: system_sdk.events.WindowId) void {
        self.sdk = sdk;
        self.window_id = window_id;
        self.enabled = if (sdk) |bound_sdk| bound_sdk.getCapabilities().has(.accessibility) else false;
    }

    pub fn clearSystemSdk(self: *AccessibilityBridge) void {
        self.sdk = null;
        self.enabled = false;
    }

    pub fn setWindowId(self: *AccessibilityBridge, window_id: system_sdk.events.WindowId) void {
        self.window_id = window_id;
    }

    pub fn notifyFocusChange(self: *AccessibilityBridge, node: ?*Node) void {
        if (!self.enabled or !self.automatic_focus_notifications) return;
        const snapshot = a11ySnapshotForNode(node orelse return) orelse return;
        const sdk = self.sdk orelse return;
        sdk.notifyAccessibilityFocus(self.window_id, snapshot) catch {};
    }

    pub fn announceText(self: *AccessibilityBridge, text: []const u8) void {
        if (!self.enabled) return;
        const sdk = self.sdk orelse return;
        sdk.announceAccessibilityText(self.window_id, text) catch {};
    }

    pub fn notifyPropertyChange(self: *AccessibilityBridge, node: *Node) void {
        if (!self.enabled) return;
        const snapshot = a11ySnapshotForNode(node) orelse return;
        const sdk = self.sdk orelse return;
        sdk.notifyAccessibilityPropertyChange(self.window_id, snapshot) catch {};
    }
};

fn a11ySnapshotForNode(node: *const Node) ?system_sdk.AccessibilityNodeSnapshot {
    const a11y = node.behavior.interaction.a11y orelse return a11ySnapshotForVisibleText(node);
    var snapshot = system_sdk.AccessibilityNodeSnapshot{
        .role = mapA11yRole(a11y.role),
        .label = a11y.label orelse "",
        .description = a11y.description orelse "",
        .value_text = a11y.value_text orelse "",
        .live = a11y.live orelse "",
        .checked = a11y.checked,
        .disabled = a11y.disabled,
        .expanded = a11y.expanded,
        .selected = a11y.selected,
        .required = a11y.required,
        .invalid = a11y.invalid,
        .readonly = a11y.readonly,
        .busy = a11y.busy,
        .modal = a11y.modal,
    };
    if (snapshot.label.len == 0) {
        if (node.getText()) |text| snapshot.label = text.content;
    }
    if (!snapshot.hasSemanticContent()) return null;
    return snapshot;
}

fn a11ySnapshotForVisibleText(node: *const Node) ?system_sdk.AccessibilityNodeSnapshot {
    const text = node.getText() orelse return null;
    if (text.content.len == 0) return null;
    return .{ .label = text.content };
}

fn mapA11yRole(role: A11yRole) system_sdk.AccessibilityRole {
    return switch (role) {
        .none => .none,
        .button => .button,
        .checkbox => .checkbox,
        .radio => .radio,
        .textbox => .textbox,
        .switch_role => .switch_role,
        .tab => .tab,
        .tablist => .tablist,
        .dialog => .dialog,
        .alert => .alert,
        .menu => .menu,
        .menuitem => .menuitem,
        .listbox => .listbox,
        .option => .option,
        .progressbar => .progressbar,
        .slider => .slider,
        .heading => .heading,
        .link => .link,
        .img => .img,
        .list => .list,
        .listitem => .listitem,
        .table => .table,
        .tooltip => .tooltip,
        // v0.7 §2.5
        .combobox => .combobox,
        .grid => .grid,
        .gridcell => .gridcell,
        // 2026-07-31 supplement (same batch as core.zig mapA11yRoleToTreeRole)
        .tree => .tree,
        .treeitem => .treeitem,
        .row => .row,
        .columnheader => .columnheader,
        .rowheader => .rowheader,
        .menubar => .menubar,
        .menuitemcheckbox => .menuitemcheckbox,
        .menuitemradio => .menuitemradio,
        .spinbutton => .spinbutton,
        .status => .status,
        .group => .group,
        .navigation => .navigation,
        .separator => .separator,
        .region => .region,
        .article => .article,
        .application => .application,
        .radiogroup => .radiogroup,
        .textarea => .textarea,
        .searchbox => .searchbox,
        .tabpanel => .tabpanel,
        .alertdialog => .alertdialog,
        .log => .log,
        .paragraph => .paragraph,
        .section => .section,
        .form => .form,
        .main => .main,
        .banner => .banner,
        .contentinfo => .contentinfo,
        .generic => .generic,
        // Old SystemSdk snapshot missing scroll area role, report as group.
        .scroll_area => .group,
    };
}

// ========== Tests ==========

test "FocusManager: init/deinit" {
    var fm = FocusManager.init(std.testing.allocator);
    defer fm.deinit();

    try std.testing.expectEqual(@as(?*Node, null), fm.current_focus);
    try std.testing.expectEqual(@as(usize, 0), fm.focus_order.items.len);
}

test "FocusManager: stale cached focus never bypasses registry generation" {
    const allocator = std.testing.allocator;
    var registry = NodeRegistry.init(allocator);
    defer registry.deinit();
    var fm = FocusManager.init(allocator);
    defer fm.deinit();

    const node = try Node.create(allocator, 91_001, .button, .{});
    defer node.destroy(allocator);
    try registry.rebuild(node);
    fm.setRegistry(&registry);
    fm.setFocus(node);
    try std.testing.expect(fm.getFocused() == node);

    registry.unregisterSubtree(node);
    try std.testing.expectEqual(@as(?*Node, null), fm.getFocused());
}

test "FocusManager: setFocus triggers blur/focus" {
    var fm = FocusManager.init(std.testing.allocator);
    defer fm.deinit();

    var ctx = try core.Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const FocusCtx = struct {
        focus_count: u32 = 0,
        blur_count: u32 = 0,
    };

    var ctx_a = FocusCtx{};
    var ctx_b = FocusCtx{};

    const node_a = try core.box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
    node_a.behavior.events.on_focus = core.Cx.simpleHandler(struct {
        fn handler(c: *anyopaque) void {
            const fc: *FocusCtx = @ptrCast(@alignCast(c));
            fc.focus_count += 1;
        }
    }.handler, &ctx_a);
    node_a.behavior.events.on_blur = core.Cx.simpleHandler(struct {
        fn handler(c: *anyopaque) void {
            const fc: *FocusCtx = @ptrCast(@alignCast(c));
            fc.blur_count += 1;
        }
    }.handler, &ctx_a);

    const node_b = try core.box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
    node_b.behavior.events.on_focus = core.Cx.simpleHandler(struct {
        fn handler(c: *anyopaque) void {
            const fc: *FocusCtx = @ptrCast(@alignCast(c));
            fc.focus_count += 1;
        }
    }.handler, &ctx_b);
    node_b.behavior.events.on_blur = core.Cx.simpleHandler(struct {
        fn handler(c: *anyopaque) void {
            const fc: *FocusCtx = @ptrCast(@alignCast(c));
            fc.blur_count += 1;
        }
    }.handler, &ctx_b);

    const root = try core.box(ctx, .{ .width = .{ .px = 200 }, .height = .{ .px = 100 } }, .{});
    try root.appendChild(std.testing.allocator, node_a);
    try root.appendChild(std.testing.allocator, node_b);
    ctx.root = root;

    // Focus A
    fm.setFocus(node_a);
    try std.testing.expectEqual(@as(u32, 1), ctx_a.focus_count);
    try std.testing.expectEqual(@as(u32, 0), ctx_a.blur_count);

    // Focus B (A loses focus)
    fm.setFocus(node_b);
    try std.testing.expectEqual(@as(u32, 1), ctx_a.blur_count);
    try std.testing.expectEqual(@as(u32, 1), ctx_b.focus_count);
}

test "FocusManager: Tab navigation" {
    var fm = FocusManager.init(std.testing.allocator);
    defer fm.deinit();

    var ctx = try core.Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try core.box(ctx, .{ .width = .{ .px = 200 }, .height = .{ .px = 200 } }, .{});

    const nodes = blk: {
        var result: [3]*Node = undefined;
        for (&result) |*n| {
            n.* = try core.box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
            try root.appendChild(std.testing.allocator, n.*);
            try fm.registerFocusable(n.*);
        }
        break :blk result;
    };

    ctx.root = root;

    // Initially no focus
    try std.testing.expectEqual(@as(?*Node, null), fm.current_focus);

    // Tab -> first
    fm.focusNext();
    try std.testing.expect(fm.current_focus == nodes[0]);

    // Tab -> second
    fm.focusNext();
    try std.testing.expect(fm.current_focus == nodes[1]);

    // Tab -> third
    fm.focusNext();
    try std.testing.expect(fm.current_focus == nodes[2]);

    // Tab -> first again (loop)
    fm.focusNext();
    try std.testing.expect(fm.current_focus == nodes[0]);

    // Shift+Tab -> third
    fm.focusPrev();
    try std.testing.expect(fm.current_focus == nodes[2]);
}

test "FocusManager: registerFocusable no duplicates" {
    var fm = FocusManager.init(std.testing.allocator);
    defer fm.deinit();

    var ctx = try core.Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try core.box(ctx, .{ .width = .{ .px = 200 }, .height = .{ .px = 100 } }, .{});
    const node = try core.box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
    try root.appendChild(std.testing.allocator, node);
    ctx.root = root;

    try fm.registerFocusable(node);
    try fm.registerFocusable(node);
    try fm.registerFocusable(node);

    try std.testing.expectEqual(@as(usize, 1), fm.focus_order.items.len);
}

test "FocusManager: unregisterFocusable" {
    var fm = FocusManager.init(std.testing.allocator);
    defer fm.deinit();

    var ctx = try core.Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try core.box(ctx, .{ .width = .{ .px = 200 }, .height = .{ .px = 100 } }, .{});
    const node = try core.box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
    try root.appendChild(std.testing.allocator, node);
    ctx.root = root;

    try fm.registerFocusable(node);
    try std.testing.expectEqual(@as(usize, 1), fm.focus_order.items.len);

    fm.setFocus(node);
    try std.testing.expect(fm.current_focus == node);

    fm.unregisterFocusable(node);
    try std.testing.expectEqual(@as(usize, 0), fm.focus_order.items.len);
    try std.testing.expectEqual(@as(?*Node, null), fm.current_focus);
}

test "FocusManager: collectFocusableNodes uses focusable field" {
    var fm = FocusManager.init(std.testing.allocator);
    defer fm.deinit();

    var ctx = try core.Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try core.box(ctx, .{
        .width = .{ .px = 400 },
        .height = .{ .px = 300 },
        .direction = core.Direction.column,
    }, .{});

    // Plain box (not focusable)
    const box1 = try core.box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
    try root.appendChild(std.testing.allocator, box1);

    // focusable input
    const input1 = try core.Node.create(std.testing.allocator, ctx.nextId(), .input, .{
        .width = .{ .px = 200 },
        .height = .{ .px = 30 },
    });
    input1.behavior.interaction.focusable = true;
    try root.appendChild(std.testing.allocator, input1);

    // focusable button
    const btn1 = try core.Node.create(std.testing.allocator, ctx.nextId(), .button, .{
        .width = .{ .px = 100 },
        .height = .{ .px = 30 },
    });
    btn1.behavior.interaction.focusable = true;
    try root.appendChild(std.testing.allocator, btn1);

    // focusable box (via focusable field)
    const focusable_box = try core.box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
    focusable_box.behavior.interaction.focusable = true;
    try root.appendChild(std.testing.allocator, focusable_box);

    // input without focusable flag (should NOT be collected)
    const input2 = try core.Node.create(std.testing.allocator, ctx.nextId(), .input, .{
        .width = .{ .px = 200 },
        .height = .{ .px = 30 },
    });
    try root.appendChild(std.testing.allocator, input2);

    ctx.root = root;

    try fm.collectFocusableNodes(root);
    // Only 3 focusable nodes (input1, btn1, focusable_box), not input2
    try std.testing.expectEqual(@as(usize, 3), fm.focus_order.items.len);
    try std.testing.expect(fm.focus_order.items[0] == input1);
    try std.testing.expect(fm.focus_order.items[1] == btn1);
    try std.testing.expect(fm.focus_order.items[2] == focusable_box);
}

test "Cx: click non-focusable clears focus" {
    var ctx = try core.Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try core.box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});

    // focusable button
    const btn = try core.box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
    btn.behavior.interaction.focusable = true;
    btn.behavior.events.on_event = struct {
        fn handler(_: core.Event, _: ?*anyopaque) core.EventResult {
            return .handled;
        }
    }.handler;
    try root.appendChild(std.testing.allocator, btn);

    // non-focusable area with event handler (to be hittable)
    const area = try core.box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
    area.behavior.events.on_event = struct {
        fn handler(_: core.Event, _: ?*anyopaque) core.EventResult {
            return .handled;
        }
    }.handler;
    try root.appendChild(std.testing.allocator, area);

    ctx.root = root;
    ctx.setViewport(400, 300);
    ctx.layout();

    // Click focusable button first
    ctx.handleMouseDown(50, 15, .{});
    ctx.handleMouseUp(50, 15);
    try std.testing.expect(ctx.focus_manager.current_focus == btn);

    // Click non-focusable area -> clears focus
    ctx.handleMouseDown(50, 45, .{});
    ctx.handleMouseUp(50, 45);
    try std.testing.expectEqual(@as(?*Node, null), ctx.focus_manager.current_focus);
}

test "Cx: click focusable node sets focus" {
    var ctx = try core.Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try core.box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});

    const btn = try core.box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
    btn.behavior.interaction.focusable = true;
    btn.behavior.events.on_event = struct {
        fn handler(_: core.Event, _: ?*anyopaque) core.EventResult {
            return .handled;
        }
    }.handler;
    try root.appendChild(std.testing.allocator, btn);

    ctx.root = root;
    ctx.setViewport(400, 300);
    ctx.layout();

    // Initially no focus
    try std.testing.expectEqual(@as(?*Node, null), ctx.focus_manager.current_focus);

    // Click focusable node -> gets focus
    ctx.handleMouseDown(50, 15, .{});
    ctx.handleMouseUp(50, 15);
    try std.testing.expect(ctx.focus_manager.current_focus == btn);
}

test "Cx: click child of focusable finds ancestor" {
    var ctx = try core.Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try core.box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});

    // focusable parent container
    const container = try core.box(ctx, .{
        .width = .{ .px = 200 },
        .height = .{ .px = 50 },
    }, .{});
    container.behavior.interaction.focusable = true;
    container.behavior.events.on_event = struct {
        fn handler(_: core.Event, _: ?*anyopaque) core.EventResult {
            return .handled;
        }
    }.handler;
    try root.appendChild(std.testing.allocator, container);

    // non-focusable child inside focusable container
    const child = try core.box(ctx, .{
        .width = .{ .px = 80 },
        .height = .{ .px = 30 },
    }, .{});
    child.behavior.events.on_event = struct {
        fn handler(_: core.Event, _: ?*anyopaque) core.EventResult {
            return .handled;
        }
    }.handler;
    try container.appendChild(std.testing.allocator, child);

    ctx.root = root;
    ctx.setViewport(400, 300);
    ctx.layout();

    // Click child -> focus goes to focusable ancestor (container)
    ctx.handleMouseDown(40, 15, .{});
    ctx.handleMouseUp(40, 15);
    try std.testing.expect(ctx.focus_manager.current_focus == container);
}

// ── pointer_down_focus = .preserve ────────────────────────────────────
// Scenario: focusable "editor" holds focus; focusable=false button nested in two
// focusable=false containers (toolbar -> group). `preserve_on` determines which level
// gets .preserve (null = unset, use default transfer).

const PdfPlacement = enum {
    /// Button in editor subtree (editor is button's nearest focusable ancestor).
    inside_editor,
    /// Button outside editor sibling subtree (floating toolbar elsewhere, no focusable in
    /// parent chain).
    sibling_of_editor,
    /// Button inside different focusable panel (nearest focusable ancestor not editor).
    inside_focusable_panel,
};

const PdfPreserveOn = enum { none, toolbar, button };

const PdfFixture = struct {
    ctx: *core.Cx,
    editor: *Node,
    panel: ?*Node,
    button: *Node,
    /// Button center (window coords)
    button_xy: [2]f32,
    /// Editor point not covered by other child nodes
    editor_xy: [2]f32,
};

fn pdfHandled(_: core.Event, _: ?*anyopaque) core.EventResult {
    return .handled;
}

fn pdfBox(ctx: *core.Cx, w: f32, h: f32) !*Node {
    const n = try core.box(ctx, .{
        .width = .{ .px = w },
        .height = .{ .px = h },
        .direction = core.Direction.column,
    }, .{});
    n.behavior.events.on_event = pdfHandled;
    return n;
}

fn buildPdfFixture(ctx: *core.Cx, placement: PdfPlacement, preserve_on: PdfPreserveOn) !PdfFixture {
    const a = std.testing.allocator;
    const root = try core.box(ctx, .{
        .width = .{ .px = 400 },
        .height = .{ .px = 300 },
        .direction = core.Direction.column,
    }, .{});
    ctx.root = root;

    const editor = try pdfBox(ctx, 400, 100);
    editor.behavior.interaction.focusable = true;
    try root.appendChild(a, editor);

    const toolbar = try pdfBox(ctx, 200, 40);
    const group = try pdfBox(ctx, 150, 30);
    const button = try pdfBox(ctx, 60, 20);
    try group.appendChild(a, button);
    try toolbar.appendChild(a, group);

    var panel: ?*Node = null;
    switch (placement) {
        .inside_editor => {
            // Editor content above (y 0..60), toolbar below (y 60..100).
            const body = try pdfBox(ctx, 400, 60);
            try editor.appendChild(a, body);
            try editor.appendChild(a, toolbar);
        },
        .sibling_of_editor => try root.appendChild(a, toolbar),
        .inside_focusable_panel => {
            const p = try pdfBox(ctx, 400, 100);
            p.behavior.interaction.focusable = true;
            try p.appendChild(a, toolbar);
            try root.appendChild(a, p);
            panel = p;
        },
    }

    switch (preserve_on) {
        .none => {},
        .toolbar => toolbar.setPointerDownFocus(.preserve),
        .button => button.setPointerDownFocus(.preserve),
    }

    ctx.setViewport(400, 300);
    ctx.layout();

    const toolbar_y: f32 = if (placement == .inside_editor) 60 else 100;
    return .{
        .ctx = ctx,
        .editor = editor,
        .panel = panel,
        .button = button,
        .button_xy = .{ 30, toolbar_y + 10 },
        .editor_xy = .{ 300, 20 },
    };
}

fn pdfClick(ctx: *core.Cx, xy: [2]f32) void {
    ctx.handleMouseDown(xy[0], xy[1], .{});
    ctx.handleMouseUp(xy[0], xy[1]);
}

/// Click editor first to gain focus, then button; check focus after button click.
fn pdfFocusAfterButtonClick(placement: PdfPlacement, preserve_on: PdfPreserveOn) !struct { focus: ?*Node, fx: PdfFixture, ctx: *core.Cx } {
    const ctx = try core.Cx.init(std.testing.allocator, std.testing.io);
    errdefer ctx.deinit();
    const fx = try buildPdfFixture(ctx, placement, preserve_on);

    pdfClick(ctx, fx.editor_xy);
    try std.testing.expect(ctx.focus_manager.current_focus == fx.editor);

    pdfClick(ctx, fx.button_xy);
    // Hit truly on button (else assertion tests different node).
    try std.testing.expect(ctx.last_mouse_down_target == fx.button);
    return .{ .focus = ctx.focus_manager.current_focus, .fx = fx, .ctx = ctx };
}

test "Cx: pointer_down_focus defaults to transfer" {
    const ctx = try core.Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const n = try core.box(ctx, .{}, .{});
    ctx.root = n;
    try std.testing.expectEqual(core.PointerDownFocus.transfer, n.behavior.interaction.pointer_down_focus);
}

test "Cx: pointer_down_focus button under focused editor — default and preserve both keep editor" {
    // Editor itself is nearest focusable ancestor: default transfer target is current
    // focus.
    {
        const r = try pdfFocusAfterButtonClick(.inside_editor, .none);
        defer r.ctx.deinit();
        try std.testing.expect(r.focus == r.fx.editor);
    }
    {
        const r = try pdfFocusAfterButtonClick(.inside_editor, .toolbar);
        defer r.ctx.deinit();
        try std.testing.expect(r.focus == r.fx.editor);
        try std.testing.expect(r.ctx.focused_node == r.fx.editor);
    }
}

test "Cx: pointer_down_focus preserve keeps editor focus when toolbar is outside editor" {
    {
        // Contrast: default behavior, no focusable in parent chain -> clear focus.
        const r = try pdfFocusAfterButtonClick(.sibling_of_editor, .none);
        defer r.ctx.deinit();
        try std.testing.expectEqual(@as(?*Node, null), r.focus);
    }
    {
        const r = try pdfFocusAfterButtonClick(.sibling_of_editor, .toolbar);
        defer r.ctx.deinit();
        try std.testing.expect(r.focus == r.fx.editor);
        try std.testing.expect(r.ctx.focused_node == r.fx.editor);
        try std.testing.expect(r.ctx.focused_handle != null);
    }
}

test "Cx: pointer_down_focus preserve stops walk before a focusable panel ancestor" {
    {
        // Contrast: default behavior, focus goes to button's nearest focusable ancestor
        // (panel).
        const r = try pdfFocusAfterButtonClick(.inside_focusable_panel, .none);
        defer r.ctx.deinit();
        try std.testing.expect(r.fx.panel != null);
        try std.testing.expect(r.focus == r.fx.panel.?);
    }
    {
        const r = try pdfFocusAfterButtonClick(.inside_focusable_panel, .toolbar);
        defer r.ctx.deinit();
        try std.testing.expect(r.focus == r.fx.editor);
    }
}

test "Cx: pointer_down_focus preserve on a focusable button wins over its own focusability" {
    {
        const r = try pdfFocusAfterButtonClick(.sibling_of_editor, .button);
        defer r.ctx.deinit();
        try std.testing.expect(r.focus == r.fx.editor);
    }
    {
        // Button focusable + preserve: still not focus-grabbing (Tab-able but click does not
        // grab).
        const ctx = try core.Cx.init(std.testing.allocator, std.testing.io);
        defer ctx.deinit();
        const fx = try buildPdfFixture(ctx, .sibling_of_editor, .button);
        fx.button.behavior.interaction.focusable = true;
        pdfClick(ctx, fx.editor_xy);
        try std.testing.expect(ctx.focus_manager.current_focus == fx.editor);
        pdfClick(ctx, fx.button_xy);
        try std.testing.expect(ctx.last_mouse_down_target == fx.button);
        try std.testing.expect(ctx.focus_manager.current_focus == fx.editor);
    }
}

test "Cx: pointer_down_focus preserve does not block a focusable descendant" {
    // Toolbar sets .preserve, but button focusable (e.g., embedded input in toolbar):
    // from hit node upward, first focusable -> normal focus grab.
    const ctx = try core.Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const fx = try buildPdfFixture(ctx, .sibling_of_editor, .toolbar);
    fx.button.behavior.interaction.focusable = true;
    pdfClick(ctx, fx.editor_xy);
    try std.testing.expect(ctx.focus_manager.current_focus == fx.editor);
    pdfClick(ctx, fx.button_xy);
    try std.testing.expect(ctx.focus_manager.current_focus == fx.button);
}

test "Cx: pointer_down_focus preserve with nothing focused stays unfocused and still dispatches" {
    const ctx = try core.Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const fx = try buildPdfFixture(ctx, .sibling_of_editor, .toolbar);
    const Counter = struct {
        var downs: u32 = 0;
        fn handler(ev: core.Event, _: ?*anyopaque) core.EventResult {
            if (ev == .mouse_down) downs += 1;
            return .handled;
        }
    };
    Counter.downs = 0;
    fx.button.behavior.events.on_event = Counter.handler;
    try std.testing.expectEqual(@as(?*Node, null), ctx.focus_manager.current_focus);
    pdfClick(ctx, fx.button_xy);
    try std.testing.expectEqual(@as(?*Node, null), ctx.focus_manager.current_focus);
    try std.testing.expectEqual(@as(u32, 1), Counter.downs);
}

test "Cx: layout auto collects focusable nodes" {
    var ctx = try core.Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try core.box(ctx, .{
        .width = .{ .px = 400 },
        .height = .{ .px = 300 },
        .direction = core.Direction.column,
    }, .{});

    const btn1 = try core.box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
    btn1.behavior.interaction.focusable = true;
    try root.appendChild(std.testing.allocator, btn1);

    const btn2 = try core.box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
    btn2.behavior.interaction.focusable = true;
    try root.appendChild(std.testing.allocator, btn2);

    // non-focusable
    const box1 = try core.box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
    try root.appendChild(std.testing.allocator, box1);

    ctx.root = root;
    ctx.setViewport(400, 300);
    ctx.layout();

    // layout should have collected 2 focusable nodes
    try std.testing.expectEqual(@as(usize, 2), ctx.focus_manager.focus_order.items.len);
    try std.testing.expect(ctx.focus_manager.focus_order.items[0] == btn1);
    try std.testing.expect(ctx.focus_manager.focus_order.items[1] == btn2);
}

test "FocusScope: push/pop" {
    var fm = FocusManager.init(std.testing.allocator);
    defer fm.deinit();

    var ctx = try core.Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try core.box(ctx, .{ .width = .{ .px = 800 }, .height = .{ .px = 600 } }, .{});
    ctx.root = root;

    const scope1 = try core.box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    scope1.behavior.interaction.focus_scope = .{ .trap = true };
    try root.appendChild(std.testing.allocator, scope1);

    const scope2 = try core.box(ctx, .{ .width = .{ .px = 200 }, .height = .{ .px = 200 } }, .{});
    scope2.behavior.interaction.focus_scope = .{ .trap = true };
    try scope1.appendChild(std.testing.allocator, scope2);

    try std.testing.expectEqual(@as(u8, 0), fm.scope_count);
    try std.testing.expectEqual(@as(?*Node, null), fm.activeScope());

    fm.pushScope(scope1);
    try std.testing.expectEqual(@as(u8, 1), fm.scope_count);
    try std.testing.expect(fm.activeScope() == scope1);

    fm.pushScope(scope2);
    try std.testing.expectEqual(@as(u8, 2), fm.scope_count);
    try std.testing.expect(fm.activeScope() == scope2);

    fm.popScope();
    try std.testing.expectEqual(@as(u8, 1), fm.scope_count);
    try std.testing.expect(fm.activeScope() == scope1);

    fm.popScope();
    try std.testing.expectEqual(@as(u8, 0), fm.scope_count);
    try std.testing.expectEqual(@as(?*Node, null), fm.activeScope());

    // pop on empty is safe
    fm.popScope();
    try std.testing.expectEqual(@as(u8, 0), fm.scope_count);
}

test "FocusScope: scope 节点释放后 activeScope 返回 null 而非悬垂指针" {
    const allocator = std.testing.allocator;
    var registry = NodeRegistry.init(allocator);
    defer registry.deinit();
    var fm = FocusManager.init(allocator);
    defer fm.deinit();

    const modal = try Node.create(allocator, 91_002, .button, .{});
    defer modal.destroy(allocator);
    modal.behavior.interaction.focus_scope = .{ .trap = true };
    try registry.rebuild(modal);
    fm.setRegistry(&registry);

    fm.pushScope(modal);
    // Successful parse caches raw pointer into scope_stack
    try std.testing.expect(fm.activeScope() == modal);

    // Simulate scope node freed (freeNode -> noteNodeFreed unlinks table entry)
    registry.unregisterSubtree(modal);
    try std.testing.expect(fm.activeScope() == null);
    // Tab path (scopedFocusOrder) takes no-scope branch, does not dereference dangling
    // scope
    try std.testing.expectEqual(fm.focus_order.items.len, fm.scopedFocusOrder().len);
}

test "FocusScope: tab stays within trap" {
    var fm = FocusManager.init(std.testing.allocator);
    defer fm.deinit();

    var ctx = try core.Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try core.box(ctx, .{ .width = .{ .px = 800 }, .height = .{ .px = 600 } }, .{});

    // Outside button (should be excluded from trap navigation)
    const outside_btn = try core.box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
    outside_btn.behavior.interaction.focusable = true;
    try root.appendChild(std.testing.allocator, outside_btn);

    // Modal scope
    const modal = try core.box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    modal.behavior.interaction.focus_scope = .{ .trap = true };
    try root.appendChild(std.testing.allocator, modal);

    const btn_a = try core.box(ctx, .{ .width = .{ .px = 80 }, .height = .{ .px = 30 } }, .{});
    btn_a.behavior.interaction.focusable = true;
    try modal.appendChild(std.testing.allocator, btn_a);

    const btn_b = try core.box(ctx, .{ .width = .{ .px = 80 }, .height = .{ .px = 30 } }, .{});
    btn_b.behavior.interaction.focusable = true;
    try modal.appendChild(std.testing.allocator, btn_b);

    ctx.root = root;

    // Collect focusable nodes (3 total: outside_btn, btn_a, btn_b)
    try fm.collectFocusableNodes(root);
    try std.testing.expectEqual(@as(usize, 3), fm.focus_order.items.len);

    // Push trap scope
    fm.pushScope(modal);

    // Scoped order should only contain btn_a, btn_b
    const scoped = fm.scopedFocusOrder();
    try std.testing.expectEqual(@as(usize, 2), scoped.len);

    // Tab navigation stays within trap
    fm.setFocus(btn_a);
    fm.focusNext();
    try std.testing.expect(fm.current_focus == btn_b);

    fm.focusNext();
    try std.testing.expect(fm.current_focus == btn_a); // wraps back

    fm.focusPrev();
    try std.testing.expect(fm.current_focus == btn_b); // wraps back

    fm.popScope();
}

test "FocusScope: isDescendantOf" {
    var ctx = try core.Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try core.box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;

    const parent_node = try core.box(ctx, .{ .width = .{ .px = 200 }, .height = .{ .px = 200 } }, .{});
    try root.appendChild(std.testing.allocator, parent_node);
    const child = try core.box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 100 } }, .{});
    try parent_node.appendChild(std.testing.allocator, child);
    const grandchild = try core.box(ctx, .{ .width = .{ .px = 50 }, .height = .{ .px = 50 } }, .{});
    try child.appendChild(std.testing.allocator, grandchild);

    const unrelated = try core.box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 100 } }, .{});
    try root.appendChild(std.testing.allocator, unrelated);

    try std.testing.expect(grandchild.isDescendantOf(root));
    try std.testing.expect(grandchild.isDescendantOf(parent_node));
    try std.testing.expect(grandchild.isDescendantOf(child));
    try std.testing.expect(grandchild.isDescendantOf(grandchild)); // node is descendant of itself
    try std.testing.expect(!grandchild.isDescendantOf(unrelated));
    try std.testing.expect(!unrelated.isDescendantOf(parent_node));
}

test "FocusEvent: blur carries related_node_id" {
    var ctx = try core.Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try core.box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;

    const node_a = try core.box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
    node_a.behavior.interaction.focusable = true;
    try root.appendChild(std.testing.allocator, node_a);

    const node_b = try core.box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
    node_b.behavior.interaction.focusable = true;
    try root.appendChild(std.testing.allocator, node_b);

    const TestCtx = struct {
        var last_blur_related: ?u32 = null;
        var last_focus_related: ?u32 = null;
        var last_focus_reason: FocusReason = .programmatic;
    };
    TestCtx.last_blur_related = null;
    TestCtx.last_focus_related = null;
    TestCtx.last_focus_reason = .programmatic;

    // Must layout first to register nodes in registry before dispatcher can dispatch
    // events
    ctx.layout();

    // Set on_event to capture FocusEvent details
    node_a.behavior.events.on_event = struct {
        fn handler(event: Event, _: ?*anyopaque) events_mod.EventResult {
            switch (event) {
                .blur => |fe| {
                    TestCtx.last_blur_related = fe.related_node_id;
                },
                else => {},
            }
            return .ignored;
        }
    }.handler;

    node_b.behavior.events.on_event = struct {
        fn handler(event: Event, _: ?*anyopaque) events_mod.EventResult {
            switch (event) {
                .focus => |fe| {
                    TestCtx.last_focus_related = fe.related_node_id;
                    TestCtx.last_focus_reason = fe.reason;
                },
                else => {},
            }
            return .ignored;
        }
    }.handler;

    // Focus A first
    ctx.focus_manager.setFocusWithReason(node_a, .click);

    // Focus B (A blurs)
    ctx.focus_manager.setFocusWithReason(node_b, .tab);

    // A's blur should carry B's id as related
    try std.testing.expectEqual(node_b.id, TestCtx.last_blur_related.?);
    // B's focus should carry A's id as related
    try std.testing.expectEqual(node_a.id, TestCtx.last_focus_related.?);
    // B's focus reason should be .tab
    try std.testing.expectEqual(FocusReason.tab, TestCtx.last_focus_reason);
}

test "FocusEvent: focus reason click/tab/programmatic" {
    var ctx = try core.Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try core.box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;

    const node = try core.box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
    node.behavior.interaction.focusable = true;
    try root.appendChild(std.testing.allocator, node);

    const TestCtx2 = struct {
        var last_reason: FocusReason = .programmatic;
    };

    node.behavior.events.on_event = struct {
        fn handler(event: Event, _: ?*anyopaque) events_mod.EventResult {
            switch (event) {
                .focus => |fe| {
                    TestCtx2.last_reason = fe.reason;
                },
                else => {},
            }
            return .ignored;
        }
    }.handler;

    ctx.layout();

    // Test click reason
    ctx.focus_manager.setFocusWithReason(node, .click);
    try std.testing.expectEqual(FocusReason.click, TestCtx2.last_reason);

    // Clear and test tab reason
    ctx.focus_manager.clearFocus();
    ctx.focus_manager.setFocusWithReason(node, .tab);
    try std.testing.expectEqual(FocusReason.tab, TestCtx2.last_reason);

    // Clear and test programmatic reason
    ctx.focus_manager.clearFocus();
    ctx.focus_manager.setFocus(node); // default is .programmatic
    try std.testing.expectEqual(FocusReason.programmatic, TestCtx2.last_reason);
}

test "FocusEvent: bubbles via dispatch" {
    var ctx = try core.Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try core.box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;

    var parent_got_focus = false;

    const parent_node = try core.box(ctx, .{ .width = .{ .px = 200 }, .height = .{ .px = 100 } }, .{});
    parent_node.behavior.events.on_event = struct {
        fn handler(event: Event, context: ?*anyopaque) events_mod.EventResult {
            switch (event) {
                .focus => {
                    const ptr: *bool = @ptrCast(@alignCast(context.?));
                    ptr.* = true;
                },
                else => {},
            }
            return .ignored;
        }
    }.handler;
    parent_node.behavior.events.event_context = &parent_got_focus;
    try root.appendChild(std.testing.allocator, parent_node);

    const child = try core.box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
    child.behavior.interaction.focusable = true;
    try parent_node.appendChild(std.testing.allocator, child);

    ctx.layout();

    // Focus child, should bubble to parent's on_event
    ctx.focus_manager.setFocus(child);
    try std.testing.expect(parent_got_focus);
}

test "Focus memory: restore after popScope" {
    var ctx = try core.Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try core.box(ctx, .{ .width = .{ .px = 800 }, .height = .{ .px = 600 } }, .{});
    ctx.root = root;

    // Outer button
    const outer_btn = try core.box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
    outer_btn.behavior.interaction.focusable = true;
    try root.appendChild(std.testing.allocator, outer_btn);

    // Modal scope
    const modal = try core.box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    modal.behavior.interaction.focus_scope = .{ .trap = true };
    try root.appendChild(std.testing.allocator, modal);

    const inner_btn = try core.box(ctx, .{ .width = .{ .px = 80 }, .height = .{ .px = 30 } }, .{});
    inner_btn.behavior.interaction.focusable = true;
    try modal.appendChild(std.testing.allocator, inner_btn);

    ctx.setViewport(800, 600);
    ctx.layout();

    // Focus outer button
    ctx.focus_manager.setFocus(outer_btn);
    try std.testing.expect(ctx.focus_manager.current_focus == outer_btn);

    // Push modal scope, saves outer_btn focus
    ctx.focus_manager.pushScope(modal);
    // Focus moves to inner_btn (or manually set)
    ctx.focus_manager.setFocus(inner_btn);
    try std.testing.expect(ctx.focus_manager.current_focus == inner_btn);

    // Pop scope, restores outer_btn focus
    ctx.focus_manager.popScope();
    try std.testing.expect(ctx.focus_manager.current_focus == outer_btn);
}

test "Focus memory: removing an outer overlay keeps the inner scope active" {
    const a = std.testing.allocator;
    const cx = try core.Cx.init(a, std.testing.io);
    defer cx.deinit();
    const root = try core.box(cx, .{ .width = .fixed(640), .height = .fixed(480) }, .{});
    cx.root = root;
    const trigger = try core.box(cx, .{}, .{});
    const outer = try core.box(cx, .{}, .{});
    const nested_trigger = try core.box(cx, .{}, .{});
    const inner = try core.box(cx, .{}, .{});
    try root.appendChild(a, trigger);
    try root.appendChild(a, outer);
    try outer.appendChild(a, nested_trigger);
    // The overlay portal is a sibling of the outer overlay.
    try root.appendChild(a, inner);
    cx.layout();

    const fm = &cx.focus_manager;
    fm.setFocus(trigger);
    fm.pushScope(outer);
    fm.setFocus(nested_trigger);
    fm.pushScope(inner);
    fm.setFocus(inner);
    fm.removeScope(outer.id, true);
    try std.testing.expectEqual(inner, fm.activeScope().?);
    try std.testing.expectEqual(inner, fm.getFocused().?);
    fm.removeScope(inner.id, true);
    try std.testing.expectEqual(trigger, fm.getFocused().?);
}

test "Scope entry: default_return is where focus goes back; a named return only for the active scope" {
    const a = std.testing.allocator;
    const cx = try core.Cx.init(a, std.testing.io);
    defer cx.deinit();
    const root = try core.box(cx, .{ .width = .fixed(640), .height = .fixed(480) }, .{});
    cx.root = root;
    const opener = try core.box(cx, .{ .width = .fixed(40), .height = .fixed(20) }, .{});
    const trigger = try core.box(cx, .{ .width = .fixed(40), .height = .fixed(20) }, .{});
    const elsewhere = try core.box(cx, .{ .width = .fixed(40), .height = .fixed(20) }, .{});
    const panel = try core.box(cx, .{ .width = .fixed(200), .height = .fixed(100) }, .{});
    const upper = try core.box(cx, .{ .width = .fixed(200), .height = .fixed(100) }, .{});
    for ([_]*Node{ opener, trigger, elsewhere }) |n| n.behavior.interaction.focusable = true;
    for ([_]*Node{ opener, trigger, elsewhere, panel, upper }) |n| try root.appendChild(a, n);
    _ = try cx.focus_targets.register(cx, .target, elsewhere, "elsewhere", false);
    cx.layout();
    const fm = &cx.focus_manager;
    fm.setFocus(opener);
    fm.pushScopeWith(panel, .{ .default_return = trigger });
    fm.removeScopeWith(panel.id, .{ .restore = true });
    try std.testing.expectEqual(trigger, fm.getFocused().?);
    // Named return (resolved once the scope is gone), not ready = the default.
    fm.pushScopeWith(panel, .{ .default_return = opener });
    fm.removeScopeWith(panel.id, .{ .restore = true, .return_focus = "elsewhere" });
    try std.testing.expectEqual(elsewhere, fm.getFocused().?);
    fm.pushScopeWith(panel, .{ .default_return = opener });
    fm.removeScopeWith(panel.id, .{ .restore = true, .return_focus = "missing" });
    try std.testing.expectEqual(opener, fm.getFocused().?);
    // A scope removed from under another: the active one keeps focus.
    fm.pushScopeWith(panel, .{ .default_return = opener });
    fm.pushScope(upper);
    fm.setFocus(upper);
    fm.removeScopeWith(panel.id, .{ .restore = true, .return_focus = "elsewhere" });
    try std.testing.expectEqual(upper, fm.getFocused().?);
    fm.removeScope(upper.id, false);
}

test "Scope entry: a pending entry ends at user input, at another scope pushed over it, and at any other transition" {
    const a = std.testing.allocator;
    const cx = try core.Cx.init(a, std.testing.io);
    defer cx.deinit();
    const root = try core.box(cx, .{ .width = .fixed(640), .height = .fixed(480) }, .{});
    cx.root = root;
    const outside = try core.box(cx, .{ .width = .fixed(40), .height = .fixed(20) }, .{});
    outside.behavior.interaction.focusable = true;
    // A focus-trapping panel that can hold focus itself (tabindex -1), with nothing focusable yet.
    const panel = try core.box(cx, .{ .width = .fixed(200), .height = .fixed(100) }, .{});
    panel.behavior.interaction.focusable = true;
    panel.behavior.interaction.tab_index = -1;
    panel.behavior.interaction.focus_scope = .{ .trap = true, .auto_focus = true };
    const upper = try core.box(cx, .{ .width = .fixed(200), .height = .fixed(100) }, .{});
    try root.appendChild(a, outside);
    try root.appendChild(a, panel);
    try root.appendChild(a, upper);
    cx.layout();
    _ = cx.render();
    const fm = &cx.focus_manager;
    const Case = enum { input, push, transition };
    for ([_]Case{ .input, .push, .transition }) |case| {
        fm.setFocus(outside);
        fm.pushScope(panel);
        try std.testing.expectEqual(panel, fm.getFocused().?);
        try std.testing.expect(fm.scope_entry != null);
        switch (case) {
            .input => fm.noteUserInput(),
            .push => fm.pushScope(upper),
            .transition => fm.setFocus(panel),
        }
        if (case == .push) fm.removeScope(upper.id, false);
        const control = try core.box(cx, .{ .width = .fixed(40), .height = .fixed(20) }, .{});
        control.behavior.interaction.focusable = true;
        try panel.appendChild(a, control);
        cx.layout();
        _ = cx.render();
        try std.testing.expect(fm.scope_entry == null);
        try std.testing.expectEqual(panel, fm.getFocused().?);
        fm.removeScope(panel.id, false);
        panel.removeChild(control);
        cx.freeNode(control);
    }
}

test "Focus memory: auto_focus on push" {
    var ctx = try core.Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try core.box(ctx, .{ .width = .{ .px = 800 }, .height = .{ .px = 600 } }, .{});
    ctx.root = root;

    // Modal scope with auto_focus
    const modal = try core.box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    modal.behavior.interaction.focus_scope = .{ .trap = true, .auto_focus = true };
    try root.appendChild(std.testing.allocator, modal);

    const btn_a = try core.box(ctx, .{ .width = .{ .px = 80 }, .height = .{ .px = 30 } }, .{});
    btn_a.behavior.interaction.focusable = true;
    try modal.appendChild(std.testing.allocator, btn_a);

    const btn_b = try core.box(ctx, .{ .width = .{ .px = 80 }, .height = .{ .px = 30 } }, .{});
    btn_b.behavior.interaction.focusable = true;
    try modal.appendChild(std.testing.allocator, btn_b);

    ctx.setViewport(800, 600);
    ctx.layout();

    // Initially no focus
    try std.testing.expectEqual(@as(?*Node, null), ctx.focus_manager.current_focus);

    // Push scope with auto_focus -> first focusable node in scope should be focused
    ctx.focus_manager.pushScope(modal);
    try std.testing.expect(ctx.focus_manager.current_focus == btn_a);

    ctx.focus_manager.popScope();
}

// ========== Tab Index Tests ==========

test "tab_index=0 auto focusable via collectFocusableNodes" {
    var fm = FocusManager.init(std.testing.allocator);
    defer fm.deinit();

    var ctx = try core.Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try core.box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});

    // tab_index=0 node should auto-focus
    const btn = try core.box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
    btn.behavior.interaction.tab_index = 0;
    try root.appendChild(std.testing.allocator, btn);

    // Plain node (not focusable)
    const plain = try core.box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
    try root.appendChild(std.testing.allocator, plain);

    ctx.root = root;

    try fm.collectFocusableNodes(root);
    // tab_index=0 collected, plain not collected
    try std.testing.expectEqual(@as(usize, 1), fm.focus_order.items.len);
    try std.testing.expect(fm.focus_order.items[0] == btn);
}

test "tab_index=-1 excluded from Tab cycle" {
    var fm = FocusManager.init(std.testing.allocator);
    defer fm.deinit();

    var ctx = try core.Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try core.box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});

    // tab_index=-1: focusable but not in Tab cycle
    const hidden = try core.box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
    hidden.behavior.interaction.tab_index = -1;
    try root.appendChild(std.testing.allocator, hidden);

    // tab_index=0: normal Tab cycle participation
    const visible = try core.box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
    visible.behavior.interaction.tab_index = 0;
    try root.appendChild(std.testing.allocator, visible);

    ctx.root = root;

    try fm.collectFocusableNodes(root);
    // Only visible nodes in focus_order
    try std.testing.expectEqual(@as(usize, 1), fm.focus_order.items.len);
    try std.testing.expect(fm.focus_order.items[0] == visible);

    // But tab_index=-1 node still focusable via setFocus
    fm.setFocus(hidden);
    try std.testing.expect(fm.current_focus == hidden);
}

test "tab_index positive controls Tab order" {
    var fm = FocusManager.init(std.testing.allocator);
    defer fm.deinit();

    var ctx = try core.Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try core.box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});

    // Tree order: c (tab_index=3), a (tab_index=1), b (tab_index=2), d (focusable, no
    // tab_index)
    const c = try core.box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
    c.behavior.interaction.tab_index = 3;
    try root.appendChild(std.testing.allocator, c);

    const a = try core.box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
    a.behavior.interaction.tab_index = 1;
    try root.appendChild(std.testing.allocator, a);

    const b = try core.box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
    b.behavior.interaction.tab_index = 2;
    try root.appendChild(std.testing.allocator, b);

    const d = try core.box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
    d.behavior.interaction.focusable = true; // no tab_index, sorts after positive
    try root.appendChild(std.testing.allocator, d);

    ctx.root = root;

    try fm.collectFocusableNodes(root);
    // Sorted: a(1), b(2), c(3), d(tree end)
    try std.testing.expectEqual(@as(usize, 4), fm.focus_order.items.len);
    try std.testing.expect(fm.focus_order.items[0] == a);
    try std.testing.expect(fm.focus_order.items[1] == b);
    try std.testing.expect(fm.focus_order.items[2] == c);
    try std.testing.expect(fm.focus_order.items[3] == d);

    // Tab navigation follows sort order
    fm.focusNext();
    try std.testing.expect(fm.current_focus == a);
    fm.focusNext();
    try std.testing.expect(fm.current_focus == b);
    fm.focusNext();
    try std.testing.expect(fm.current_focus == c);
    fm.focusNext();
    try std.testing.expect(fm.current_focus == d);
    fm.focusNext();
    try std.testing.expect(fm.current_focus == a); // Loop
}

test "Space/Enter triggers click on focusable node" {
    var ctx = try core.Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try core.box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});

    var click_count: u32 = 0;

    const btn = try core.box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
    btn.behavior.interaction.focusable = true;
    btn.behavior.events.on_click = core.Cx.simpleHandler(struct {
        fn handler(c: *anyopaque) void {
            const cnt: *u32 = @ptrCast(@alignCast(c));
            cnt.* += 1;
        }
    }.handler, &click_count);
    try root.appendChild(std.testing.allocator, btn);

    ctx.root = root;
    ctx.setViewport(400, 300);
    ctx.layout();

    // Focus btn
    ctx.focus_manager.setFocus(btn);
    try std.testing.expect(ctx.focus_manager.current_focus == btn);

    // Space triggers click
    ctx.handleKeyDown(.space, .{});
    try std.testing.expectEqual(@as(u32, 1), click_count);

    // Enter triggers click
    ctx.handleKeyDown(.@"return", .{});
    try std.testing.expectEqual(@as(u32, 2), click_count);
}

test "Space/Enter does not override node key handler" {
    var ctx = try core.Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try core.box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});

    var click_count: u32 = 0;
    var key_count: u32 = 0;

    const input_node = try core.box(ctx, .{ .width = .{ .px = 200 }, .height = .{ .px = 30 } }, .{});
    input_node.behavior.interaction.focusable = true;
    input_node.behavior.events.on_click = core.Cx.simpleHandler(struct {
        fn handler(c: *anyopaque) void {
            const cnt: *u32 = @ptrCast(@alignCast(c));
            cnt.* += 1;
        }
    }.handler, &click_count);
    // Node self-handles key_down -> returns .handled (not .ignored)
    input_node.behavior.events.on_event = struct {
        fn handler(event: core.Event, context: ?*anyopaque) events_mod.EventResult {
            switch (event) {
                .key_down => {
                    const cnt: *u32 = @ptrCast(@alignCast(context.?));
                    cnt.* += 1;
                    return .handled;
                },
                else => return .ignored,
            }
        }
    }.handler;
    input_node.behavior.events.event_context = &key_count;
    try root.appendChild(std.testing.allocator, input_node);

    ctx.root = root;
    ctx.setViewport(400, 300);
    ctx.layout();

    ctx.focus_manager.setFocus(input_node);

    // Enter -> node handled key_down, should not synthesize click
    ctx.handleKeyDown(.@"return", .{});
    try std.testing.expectEqual(@as(u32, 1), key_count);
    try std.testing.expectEqual(@as(u32, 0), click_count); // click does not trigger
}

// ========== Accessibility bridge tests ==========

test "A11yProps: default values" {
    const props = core.A11yProps{};
    try std.testing.expectEqual(A11yRole.none, props.role);
    try std.testing.expectEqual(@as(?[]const u8, null), props.label);
    try std.testing.expectEqual(@as(?bool, null), props.checked);
    try std.testing.expect(!props.disabled);
}

test "AccessibilityBridge: notifyFocusChange smoke" {
    var bridge = AccessibilityBridge{};
    bridge.notifyFocusChange(null);

    var ctx = try core.Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try core.box(ctx, .{ .width = .{ .px = 200 }, .height = .{ .px = 100 } }, .{});
    ctx.root = root;

    const node = try core.box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
    node.behavior.interaction.a11y = .{ .role = .button, .label = "Submit" };
    try root.appendChild(std.testing.allocator, node);

    bridge.enabled = true;
    bridge.notifyFocusChange(node);
    bridge.announceText("Button focused");
    bridge.notifyPropertyChange(node);
}

test "AccessibilityBridge: forwards snapshots to SystemSdk" {
    const MockBackend = struct {
        focus_count: u32 = 0,
        property_count: u32 = 0,
        last_focus: system_sdk.AccessibilityNodeSnapshot = .{},
        last_property: system_sdk.AccessibilityNodeSnapshot = .{},

        fn deinitFn(_: *anyopaque, _: std.mem.Allocator) void {}

        fn pump(_: *anyopaque, _: *system_sdk.EventQueue, _: u32) system_sdk.SdkError!system_sdk.PumpResult {
            return .{};
        }

        fn announce(_: *anyopaque, _: system_sdk.events.WindowId, _: []const u8) system_sdk.SdkError!void {}

        fn notifyFocus(ctx_: *anyopaque, _: system_sdk.events.WindowId, snapshot: system_sdk.AccessibilityNodeSnapshot) system_sdk.SdkError!void {
            const self: *@This() = @ptrCast(@alignCast(ctx_));
            self.focus_count += 1;
            self.last_focus = snapshot;
        }

        fn notifyProperty(ctx_: *anyopaque, _: system_sdk.events.WindowId, snapshot: system_sdk.AccessibilityNodeSnapshot) system_sdk.SdkError!void {
            const self: *@This() = @ptrCast(@alignCast(ctx_));
            self.property_count += 1;
            self.last_property = snapshot;
        }
    };

    var backend = MockBackend{};
    const vtable = system_sdk.BackendVTable{
        .name = "ui-a11y-mock",
        .deinit = MockBackend.deinitFn,
        .pump_events = MockBackend.pump,
        .accessibility = .{
            .announce_text = MockBackend.announce,
            .notify_focus = MockBackend.notifyFocus,
            .notify_property_change = MockBackend.notifyProperty,
        },
    };

    var sdk = system_sdk.SystemSdk.init(std.testing.allocator, &backend, &vtable, .{ .accessibility = true });
    defer sdk.deinit();

    var bridge = AccessibilityBridge{};
    bridge.attachSystemSdk(&sdk, 3);

    var ctx = try core.Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try core.box(ctx, .{ .width = .{ .px = 160 }, .height = .{ .px = 80 } }, .{});
    ctx.root = root;

    const node = try core.box(ctx, .{ .width = .{ .px = 80 }, .height = .{ .px = 30 } }, .{});
    node.behavior.interaction.a11y = .{
        .role = .checkbox,
        .label = "Autosave",
        .checked = true,
        .disabled = true,
    };
    try root.appendChild(std.testing.allocator, node);

    bridge.notifyFocusChange(node);
    bridge.notifyPropertyChange(node);

    try std.testing.expectEqual(@as(u32, 1), backend.focus_count);
    try std.testing.expectEqual(system_sdk.AccessibilityRole.checkbox, backend.last_focus.role);
    try std.testing.expectEqualStrings("Autosave", backend.last_focus.label);
    try std.testing.expectEqual(@as(?bool, true), backend.last_focus.checked);
    try std.testing.expect(backend.last_focus.disabled);
    try std.testing.expectEqual(@as(u32, 1), backend.property_count);
    try std.testing.expectEqual(system_sdk.AccessibilityRole.checkbox, backend.last_property.role);
    try std.testing.expectEqualStrings("Autosave", backend.last_property.label);
}

test "FocusManager: focus event delivered once" {
    const cx = try core.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const node = try core.box(cx, .{}, .{});
    cx.root = node;
    node.setFocusable(true);
    const State = struct {
        count: usize = 0,
        fn event(e: core.Event, raw: ?*anyopaque) core.EventResult {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            if (e == .focus) self.count += 1;
            return .ignored;
        }
    };
    var state = State{};
    node.behavior.events.on_event = State.event;
    node.behavior.events.event_context = &state;
    cx.layout();
    _ = cx.render();
    cx.focus_manager.setFocus(node);
    try std.testing.expectEqual(@as(usize, 1), state.count);
}

test "FocusManager: blur redirect does not recursively blur old owner" {
    const cx = try core.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const root = try core.box(cx, .{}, .{});
    cx.root = root;
    const a = try core.box(cx, .{}, .{});
    const b = try core.box(cx, .{}, .{});
    const c = try core.box(cx, .{}, .{});
    try root.appendChild(cx.allocator, a);
    try root.appendChild(cx.allocator, b);
    try root.appendChild(cx.allocator, c);
    a.setFocusable(true);
    b.setFocusable(true);
    c.setFocusable(true);
    const State = struct {
        cx: *core.Cx,
        target: *core.Node,
        count: usize = 0,
        fn blur(self: *@This()) void {
            self.count += 1;
            // Bound recursion so the regression is an assertion, not a crash.
            if (self.count < 5) self.cx.focus_manager.setFocus(self.target);
        }
    };
    var state = State{ .cx = cx, .target = c };
    a.behavior.events.on_blur = core.Cx.handlerFrom(State, &state, State.blur);
    cx.layout();
    _ = cx.render();
    cx.focus_manager.setFocus(a);
    cx.focus_manager.setFocus(b);
    a.behavior.events.on_blur = null;
    try std.testing.expectEqual(@as(usize, 1), state.count);
}

test "FocusManager: mouse focus redirect keeps Cx cache consistent" {
    const cx = try core.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(400, 300);
    const root = try core.box(cx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    cx.root = root;
    const a = try core.box(cx, .{ .width = .{ .px = 100 }, .height = .{ .px = 40 } }, .{});
    const b = try core.box(cx, .{ .width = .{ .px = 100 }, .height = .{ .px = 40 } }, .{});
    try root.appendChild(cx.allocator, a);
    try root.appendChild(cx.allocator, b);
    a.setFocusable(true);
    b.setFocusable(true);
    const State = struct {
        cx: *core.Cx,
        target: *core.Node,
        fn focus(self: *@This()) void {
            self.cx.focus_manager.setFocus(self.target);
        }
        fn event(_: core.Event, _: ?*anyopaque) core.EventResult {
            return .handled;
        }
    };
    var state = State{ .cx = cx, .target = b };
    a.behavior.events.on_focus = core.Cx.handlerFrom(State, &state, State.focus);
    a.behavior.events.on_event = State.event;
    cx.layout();
    _ = cx.render();
    const r = a.rectFromWorldOrFallback();
    cx.handleMouseDown(r.x + 5, r.y + 5, .{});
    try std.testing.expectEqual(b, cx.focus_manager.getFocused().?);
    try std.testing.expectEqual(b, cx.focused_node.?);
}

test "FocusManager: mouse focus callback destroys its target" {
    const cx = try core.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(400, 300);
    const root = try core.box(cx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    cx.root = root;
    const a = try core.box(cx, .{ .width = .{ .px = 100 }, .height = .{ .px = 40 } }, .{});
    try root.appendChild(cx.allocator, a);
    a.setFocusable(true);
    const State = struct {
        cx: *core.Cx,
        target: *core.Node,
        fn focus(self: *@This()) void {
            self.cx.detachChild(self.target.parent.?, self.target);
            self.cx.freeNode(self.target);
        }
        fn event(_: core.Event, _: ?*anyopaque) core.EventResult {
            return .handled;
        }
    };
    var state = State{ .cx = cx, .target = a };
    a.behavior.events.on_focus = core.Cx.handlerFrom(State, &state, State.focus);
    a.behavior.events.on_event = State.event;
    cx.layout();
    _ = cx.render();
    const r = a.rectFromWorldOrFallback();
    cx.handleMouseDown(r.x + 5, r.y + 5, .{});
    try std.testing.expect(cx.focus_manager.getFocused() == null);
    try std.testing.expect(cx.focused_node == null);
    try std.testing.expect(cx.focused_handle == null);
}

test "FocusManager: reentrant blur requests settle once and newest request wins" {
    const Request = enum { clear, restore_old, redirect, redirect_then_destroy };
    for ([_]Request{ .clear, .restore_old, .redirect, .redirect_then_destroy }) |request| {
        const cx = try core.Cx.init(std.testing.allocator, std.testing.io);
        defer cx.deinit();
        const root = try core.box(cx, .{}, .{});
        cx.root = root;
        const a = try core.box(cx, .{}, .{});
        const b = try core.box(cx, .{}, .{});
        const c = try core.box(cx, .{}, .{});
        try root.appendChild(cx.allocator, a);
        try root.appendChild(cx.allocator, b);
        try root.appendChild(cx.allocator, c);
        const State = struct {
            cx: *core.Cx,
            old: *Node,
            target: *Node,
            request: Request,
            blur_calls: usize = 0,
            settled_calls: usize = 0,
            settled_owner: ?*Node = null,
            fn blur(self: *@This()) void {
                self.blur_calls += 1;
                // Guard makes regressions assert instead of exhausting stack.
                if (self.blur_calls > 1) return;
                switch (self.request) {
                    .clear => self.cx.clearFocus(),
                    .restore_old => self.cx.setFocus(self.old),
                    .redirect, .redirect_then_destroy => {
                        self.cx.setFocus(self.target);
                        if (self.request == .redirect_then_destroy) {
                            self.cx.detachChild(self.target.parent.?, self.target);
                            self.cx.freeNode(self.target);
                        }
                    },
                }
            }
            fn settled(ptr: *anyopaque) void {
                const self: *@This() = @ptrCast(@alignCast(ptr));
                self.settled_calls += 1;
                self.settled_owner = self.cx.focus_manager.getFocused();
            }
        };
        var state = State{ .cx = cx, .old = a, .target = c, .request = request };
        cx.layout();
        _ = cx.render();
        cx.setFocus(a);
        a.behavior.events.on_blur = core.Cx.handlerFrom(State, &state, State.blur);
        cx.focus_manager.settled_context = &state;
        cx.focus_manager.on_focus_settled = State.settled;
        cx.setFocus(b);
        a.behavior.events.on_blur = null;
        // Restore before state leaves scope / Cx teardown.
        cx.focus_manager.settled_context = null;
        cx.focus_manager.on_focus_settled = null;
        const expected: ?*Node = switch (request) {
            .clear, .redirect_then_destroy => null,
            .restore_old => a,
            .redirect => c,
        };
        try std.testing.expectEqual(@as(usize, 1), state.blur_calls);
        try std.testing.expectEqual(@as(usize, 1), state.settled_calls);
        try std.testing.expectEqual(expected, state.settled_owner);
        try std.testing.expectEqual(expected, cx.focus_manager.getFocused());
    }
}

test "FocusManager: unregistered mount target receives one focus event" {
    const cx = try core.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const node = try core.box(cx, .{}, .{});
    cx.root = node;
    const State = struct {
        count: usize = 0,
        fn event(e: Event, ptr: ?*anyopaque) core.EventResult {
            const self: *@This() = @ptrCast(@alignCast(ptr.?));
            if (e == .focus) self.count += 1;
            return .ignored;
        }
    };
    var state = State{};
    node.behavior.events.on_event = State.event;
    node.behavior.events.event_context = &state;
    cx.setFocus(node);
    try std.testing.expectEqual(@as(usize, 1), state.count);
    try std.testing.expectEqual(node, cx.focus_manager.getFocused().?);
    try std.testing.expectEqual(node, cx.focused_node.?);
}

test "FocusManager: keyboard default activation requires its original live focus owner" {
    const Mutation = enum { destroy, redirect };
    for ([_]Mutation{ .destroy, .redirect }) |mutation| {
        const cx = try core.Cx.init(std.testing.allocator, std.testing.io);
        defer cx.deinit();
        const root = try core.box(cx, .{}, .{});
        cx.root = root;
        const a = try core.box(cx, .{}, .{});
        const b = try core.box(cx, .{}, .{});
        try root.appendChild(cx.allocator, a);
        try root.appendChild(cx.allocator, b);
        a.setFocusable(true);
        b.setFocusable(true);
        const State = struct {
            cx: *core.Cx,
            source: *Node,
            other: *Node,
            mutation: Mutation,
            clicks: usize = 0,
            fn event(e: Event, ptr: ?*anyopaque) core.EventResult {
                const self: *@This() = @ptrCast(@alignCast(ptr.?));
                if (e == .key_down) {
                    switch (self.mutation) {
                        .destroy => {
                            self.cx.detachChild(self.source.parent.?, self.source);
                            self.cx.freeNode(self.source);
                        },
                        .redirect => self.cx.setFocus(self.other),
                    }
                }
                if (e == .click) self.clicks += 1;
                return .ignored;
            }
        };
        var state = State{ .cx = cx, .source = a, .other = b, .mutation = mutation };
        a.behavior.events.on_event = State.event;
        a.behavior.events.event_context = &state;
        cx.layout();
        _ = cx.render();
        cx.setFocus(a);
        cx.handleKeyDown(.@"return", .{});
        try std.testing.expectEqual(@as(usize, 0), state.clicks);
        try std.testing.expectEqual(if (mutation == .redirect) b else null, cx.focus_manager.getFocused());
    }
}

test "FocusManager: action callbacks cannot forward keys to a stale focus owner" {
    const Mutation = enum { destroy, redirect };
    for ([_]Mutation{ .destroy, .redirect }) |mutation| {
        const cx = try core.Cx.init(std.testing.allocator, std.testing.io);
        defer cx.deinit();
        const root = try core.box(cx, .{}, .{});
        cx.root = root;
        const a = try core.box(cx, .{}, .{});
        const b = try core.box(cx, .{}, .{});
        try root.appendChild(cx.allocator, a);
        try root.appendChild(cx.allocator, b);
        a.setFocusable(true);
        b.setFocusable(true);
        a.behavior.interaction.key_context = "review-keyboard";
        const State = struct {
            cx: *core.Cx,
            source: *Node,
            other: *Node,
            mutation: Mutation,
            key_calls: usize = 0,
            fn action(_: @import("actions.zig").Action, ptr: ?*anyopaque) core.EventResult {
                const self: *@This() = @ptrCast(@alignCast(ptr.?));
                switch (self.mutation) {
                    .destroy => {
                        self.cx.detachChild(self.source.parent.?, self.source);
                        self.cx.freeNode(self.source);
                    },
                    .redirect => self.cx.setFocus(self.other),
                }
                return .ignored;
            }
            fn event(e: Event, ptr: ?*anyopaque) core.EventResult {
                const self: *@This() = @ptrCast(@alignCast(ptr.?));
                if (e == .key_down) self.key_calls += 1;
                return .ignored;
            }
        };
        var state = State{ .cx = cx, .source = a, .other = b, .mutation = mutation };
        a.behavior.events.on_action = State.action;
        a.behavior.events.action_context = &state;
        a.behavior.events.on_event = State.event;
        a.behavior.events.event_context = &state;
        cx.action_dispatcher.bind(.s, .{ .super = true }, .{ .context = "review-keyboard", .name = "save" });
        cx.layout();
        _ = cx.render();
        cx.setFocus(a);
        cx.handleKeyDown(.s, .{ .super = true });
        try std.testing.expectEqual(@as(usize, 0), state.key_calls);
        try std.testing.expectEqual(if (mutation == .redirect) b else null, cx.focus_manager.getFocused());
    }
}

test "FocusManager: unregister focus does not remove callback-shifted neighbor" {
    const cx = try core.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const root = try core.box(cx, .{}, .{});
    cx.root = root;
    const a = try core.box(cx, .{}, .{});
    const b = try core.box(cx, .{}, .{});
    try root.appendChild(cx.allocator, a);
    try root.appendChild(cx.allocator, b);
    const S = struct {
        cx: *core.Cx,
        node: *core.Node,
        fn blur(self: *@This()) void {
            self.cx.focus_manager.unregisterFocusable(self.node);
        }
    };
    var state = S{ .cx = cx, .node = a };
    try cx.focus_manager.registerFocusable(a);
    try cx.focus_manager.registerFocusable(b);
    cx.setFocus(a);
    a.behavior.events.on_blur = core.Cx.handlerFrom(S, &state, S.blur);
    cx.focus_manager.unregisterFocusable(a);
    a.behavior.events.on_blur = null;
    try std.testing.expectEqual(@as(usize, 1), cx.focus_manager.focus_order.items.len);
    try std.testing.expectEqual(b, cx.focus_manager.focus_order.items[0]);
}

test "FocusManager: identity allocation failure preserves the current owner" {
    const alloc = std.testing.allocator;
    const a = try Node.create(alloc, 98001, .box, .{});
    defer a.destroy(alloc);
    const b = try Node.create(alloc, 98002, .box, .{});
    defer b.destroy(alloc);
    var fm = FocusManager.init(alloc);
    defer fm.deinit();
    fm.setFocus(a);
    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    var registry = NodeRegistry.init(failing.allocator());
    defer registry.deinit();
    fm.setRegistry(&registry);
    const State = struct {
        blurs: usize = 0,
        fn blur(self: *@This()) void {
            self.blurs += 1;
        }
    };
    var state = State{};
    a.behavior.events.on_blur = core.Cx.handlerFrom(State, &state, State.blur);
    fm.setFocus(b);
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expectEqual(a, fm.getFocused().?);
    try std.testing.expectEqual(@as(usize, 0), state.blurs);
}

test "FocusManager: settled hook may synchronously redirect again" {
    const cx = try core.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const root = try core.box(cx, .{}, .{});
    cx.root = root;
    const a = try core.box(cx, .{}, .{});
    const b = try core.box(cx, .{}, .{});
    try root.appendChild(cx.allocator, a);
    try root.appendChild(cx.allocator, b);
    const State = struct {
        cx: *core.Cx,
        target: *Node,
        original: *const fn (*anyopaque) void,
        original_context: *anyopaque,
        calls: usize = 0,
        fn settled(ptr: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            self.calls += 1;
            if (self.calls == 1) self.cx.setFocus(self.target);
            self.original(self.original_context);
        }
    };
    var state = State{
        .cx = cx,
        .target = b,
        .original = cx.focus_manager.on_focus_settled.?,
        .original_context = cx.focus_manager.settled_context.?,
    };
    cx.focus_manager.on_focus_settled = State.settled;
    cx.focus_manager.settled_context = &state;
    defer {
        cx.focus_manager.on_focus_settled = state.original;
        cx.focus_manager.settled_context = state.original_context;
    }
    cx.layout();
    _ = cx.render();
    cx.setFocus(a);
    try std.testing.expectEqual(@as(usize, 2), state.calls);
    try std.testing.expectEqual(b, cx.focus_manager.getFocused().?);
    try std.testing.expectEqual(b, cx.focused_node.?);
    try std.testing.expectEqual(cx.node_registry.handleFor(b), cx.focused_handle.?);
}

test "FocusManager: visibility observer removal and nested focus keep newest policy" {
    var cx = try core.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const node = try core.box(cx, .{}, .{});
    cx.root = node;
    const Observer = struct {
        fm: *FocusManager,
        node: *Node,
        id: u64 = 0,
        calls: usize = 0,
        guarded: bool = false,
        fn run(ptr: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            self.calls += 1;
            self.guarded = self.fm.callback_depth != 0;
            self.fm.unsubscribeVisibility(self.id);
            self.fm.setFocusWithVisibility(self.node, .programmatic, .hide);
        }
    };
    var observer: Observer = .{ .fm = &cx.focus_manager, .node = node };
    observer.id = try cx.focus_manager.subscribeVisibility(&observer, Observer.run);
    cx.focus_manager.setFocusWithReason(node, .tab);
    try std.testing.expectEqual(@as(usize, 1), observer.calls);
    try std.testing.expect(observer.guarded);
    try std.testing.expect(!cx.focus_manager.focus_visible);
    try std.testing.expectEqual(@as(usize, 0), cx.focus_manager.callback_depth);
    try std.testing.expectEqual(@as(usize, 0), cx.focus_manager.transition_depth);
}

test "FocusManager: notification cursor survives removing earlier current and later observers" {
    var fm = FocusManager.init(std.testing.allocator);
    defer fm.deinit();
    const Observer = struct {
        fm: *FocusManager,
        id: u64 = 0,
        remove_before: u64 = 0,
        remove_after: u64 = 0,
        calls: usize = 0,
        remove_self: bool = false,
        fn run(ptr: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            self.calls += 1;
            if (self.remove_before != 0) self.fm.unsubscribeVisibility(self.remove_before);
            if (self.remove_after != 0) self.fm.unsubscribeVisibility(self.remove_after);
            if (self.remove_self) self.fm.unsubscribeVisibility(self.id);
        }
    };
    var observers = [_]Observer{ .{ .fm = &fm }, .{ .fm = &fm }, .{ .fm = &fm }, .{ .fm = &fm } };
    for (&observers) |*observer| observer.id = try fm.subscribeVisibility(observer, Observer.run);
    observers[1].remove_before = observers[0].id;
    observers[1].remove_self = true;
    observers[1].remove_after = observers[2].id;
    fm.notifyVisibility();
    try std.testing.expectEqual(@as(usize, 1), observers[0].calls);
    try std.testing.expectEqual(@as(usize, 1), observers[1].calls);
    try std.testing.expectEqual(@as(usize, 0), observers[2].calls);
    try std.testing.expectEqual(@as(usize, 1), observers[3].calls);
    fm.notifyVisibility();
    try std.testing.expectEqual(@as(usize, 2), observers[3].calls);
}

test "FocusManager: focus-within runs on the subtrees focus enters / leaves, innermost first, after focus / blur" {
    const cx = try core.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const root = try core.box(cx, .{}, .{});
    cx.root = root;
    const outer = try core.box(cx, .{}, .{});
    const inner = try core.box(cx, .{}, .{});
    const a = try core.box(cx, .{}, .{});
    const b = try core.box(cx, .{}, .{});
    const c = try core.box(cx, .{}, .{});
    try root.appendChild(std.testing.allocator, outer);
    try outer.appendChild(std.testing.allocator, inner);
    try inner.appendChild(std.testing.allocator, a);
    try inner.appendChild(std.testing.allocator, b);
    try outer.appendChild(std.testing.allocator, c);
    for ([_]*Node{ a, b, c }) |n| n.setFocusable(true);
    const Log = struct {
        buf: [16]u8 = undefined,
        len: usize = 0,
        fn put(self: *@This(), ch: u8) void {
            self.buf[self.len] = ch;
            self.len += 1;
        }
        fn text(self: *const @This()) []const u8 {
            return self.buf[0..self.len];
        }
    };
    var log: Log = .{};
    const Rec = struct {
        log: *Log,
        ch: u8,
        fn run(self: *@This()) void {
            self.log.put(self.ch);
        }
    };
    var outer_in: Rec = .{ .log = &log, .ch = 'O' };
    var outer_out: Rec = .{ .log = &log, .ch = 'o' };
    var inner_in: Rec = .{ .log = &log, .ch = 'I' };
    var inner_out: Rec = .{ .log = &log, .ch = 'i' };
    var a_focus: Rec = .{ .log = &log, .ch = 'F' };
    var a_blur: Rec = .{ .log = &log, .ch = 'B' };
    outer.behavior.events.on_focus_within = core.Cx.handlerFrom(Rec, &outer_in, Rec.run);
    outer.behavior.events.on_blur_within = core.Cx.handlerFrom(Rec, &outer_out, Rec.run);
    inner.behavior.events.on_focus_within = core.Cx.handlerFrom(Rec, &inner_in, Rec.run);
    inner.behavior.events.on_blur_within = core.Cx.handlerFrom(Rec, &inner_out, Rec.run);
    a.behavior.events.on_focus = core.Cx.handlerFrom(Rec, &a_focus, Rec.run);
    a.behavior.events.on_blur = core.Cx.handlerFrom(Rec, &a_blur, Rec.run);

    cx.setFocus(a); // enters both, after a's own focus, innermost first
    try std.testing.expectEqualStrings("FIO", log.text());
    log.len = 0;
    cx.setFocus(b); // inside inner: only a's own blur, nothing enters or leaves
    try std.testing.expectEqualStrings("B", log.text());
    cx.setFocus(a);
    log.len = 0;
    cx.setFocus(c); // leaves inner only (c is still inside outer)
    try std.testing.expectEqualStrings("Bi", log.text());
    log.len = 0;
    cx.setFocus(a);
    try std.testing.expectEqualStrings("FI", log.text());
    log.len = 0;
    cx.focus_manager.clearFocus(); // leaves both
    try std.testing.expectEqualStrings("Bio", log.text());
}

test "FocusManager: a focus-within handler that moves focus stops the superseded notifications" {
    const cx = try core.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const root = try core.box(cx, .{}, .{});
    cx.root = root;
    const outer = try core.box(cx, .{}, .{});
    const inner = try core.box(cx, .{}, .{});
    const a = try core.box(cx, .{}, .{});
    const elsewhere = try core.box(cx, .{}, .{});
    try root.appendChild(std.testing.allocator, outer);
    try outer.appendChild(std.testing.allocator, inner);
    try inner.appendChild(std.testing.allocator, a);
    try root.appendChild(std.testing.allocator, elsewhere);
    a.setFocusable(true);
    elsewhere.setFocusable(true);
    const Redirect = struct {
        cx: *core.Cx,
        to: *Node,
        runs: usize = 0,
        fn run(self: *@This()) void {
            self.runs += 1;
            self.cx.setFocus(self.to);
        }
    };
    const Count = struct {
        n: usize = 0,
        fn run(self: *@This()) void {
            self.n += 1;
        }
    };
    var redirect: Redirect = .{ .cx = cx, .to = elsewhere };
    var outer_in: Count = .{};
    var outer_out: Count = .{};
    inner.behavior.events.on_focus_within = core.Cx.handlerFrom(Redirect, &redirect, Redirect.run);
    outer.behavior.events.on_focus_within = core.Cx.handlerFrom(Count, &outer_in, Count.run);
    outer.behavior.events.on_blur_within = core.Cx.handlerFrom(Count, &outer_out, Count.run);
    cx.setFocus(a);
    try std.testing.expectEqual(@as(usize, 1), redirect.runs);
    try std.testing.expect(cx.focus_manager.getFocused() == elsewhere);
    // The nested transition (a -> elsewhere) left outer; the superseded one never announced it.
    try std.testing.expectEqual(@as(usize, 0), outer_in.n);
    try std.testing.expectEqual(@as(usize, 1), outer_out.n);
}

test "FocusManager: a blur-within handler that frees an outer listener skips it" {
    const cx = try core.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const root = try core.box(cx, .{}, .{});
    cx.root = root;
    const outer = try core.box(cx, .{}, .{});
    const inner = try core.box(cx, .{}, .{});
    const a = try core.box(cx, .{}, .{});
    const elsewhere = try core.box(cx, .{}, .{});
    try root.appendChild(std.testing.allocator, outer);
    try outer.appendChild(std.testing.allocator, inner);
    try inner.appendChild(std.testing.allocator, a);
    try root.appendChild(std.testing.allocator, elsewhere);
    a.setFocusable(true);
    elsewhere.setFocusable(true);
    const Free = struct {
        cx: *core.Cx,
        victim: *Node,
        fn run(self: *@This()) void {
            self.cx.detachChild(self.victim.parent.?, self.victim);
            self.cx.freeNode(self.victim);
        }
    };
    const Count = struct {
        n: usize = 0,
        fn run(self: *@This()) void {
            self.n += 1;
        }
    };
    var free: Free = .{ .cx = cx, .victim = outer };
    var outer_out: Count = .{};
    inner.behavior.events.on_blur_within = core.Cx.handlerFrom(Free, &free, Free.run);
    outer.behavior.events.on_blur_within = core.Cx.handlerFrom(Count, &outer_out, Count.run);
    cx.setFocus(a);
    cx.setFocus(elsewhere);
    try std.testing.expectEqual(@as(usize, 0), outer_out.n);
    try std.testing.expect(cx.focus_manager.getFocused() == elsewhere);
}
