//! Conversation effects of a committed tab drop. Reordering never enters this path.
//!
//! M10：AI 对话绑定在 tab 上。拖入已有的组：被拖动 tab 的对话结束（历史保留），组 tab 的对话不变；
//! 拖到独立 tab 上新建组：目标 tab 的对话交接给新的组 tab（容器 tab），被拖动 tab 的对话结束。
//! 卡片拖出成独立 tab 不经过这里：对话留在原 tab，新 tab 没有对话。
const std = @import("std");
const assistant = @import("assistant_store.zig");
const identity = @import("../host/identity.zig");

pub const Drop = struct {
    /// 被拖动的单卡 tab（TabId 数值）。
    source: u64,
    /// Set only when dropping on an independent terminal to create a group.
    target: ?u64 = null,
    group: u32,
    /// 组 tab（容器 tab）的 TabId：新建组时目标 tab 的对话交接给它。
    container: u64,
};
pub const Activity = struct { id: u64, revision: u64, conversation: identity.ConversationId };
pub const Plan = struct {
    source: ?Activity = null,
    handoff: ?assistant.Store.Handoff = null,
    group: u32,
    /// 组 tab（容器 tab）的 TabId。
    container: u64,
};
pub const Bridge = struct {
    context: ?*anyopaque = null,
    prepare: ?*const fn (*anyopaque, Drop) anyerror!Plan = null,
    commit: ?*const fn (*anyopaque, Plan) void = null,
    capture: ?*const fn (*anyopaque, u64, ?u64) anyerror!Settlement = null,
    settle: ?*const fn (*anyopaque, Settlement) anyerror!bool = null,
    release: ?*const fn (*anyopaque, Settlement) void = null,
};
pub const Settlement = struct {
    operation: identity.HostOperationId,
    /// 被拖动的 tab 与目标 tab（TabId 数值）。
    source_tab: ?u64 = null,
    target_tab: ?u64 = null,
    source: ?@import("session_input.zig").Fence = null,
    target: ?@import("session_input.zig").Fence = null,
};
fn tabOwner(tab: u64) @import("tool_scope.zig").Owner {
    return .{ .tab = tab };
}
pub fn capture(store: *assistant.Store, source: u64, target: ?u64) !Settlement {
    var intent: Settlement = .{ .operation = identity.HostOperationId.generate(), .source_tab = source, .target_tab = target };
    if (store.authority) |service| {
        if (store.active(tabOwner(source))) |state| {
            // Empty welcome presentations have no runtime conversation yet.
            if (service.store.find(state.conversation_id) != null) intent.source = try service.store.fence(state.conversation_id);
        }
        if (target) |tab| if (store.active(tabOwner(tab))) |state| {
            if (service.store.find(state.conversation_id) != null) intent.target = try service.store.fence(state.conversation_id);
        };
    }
    return intent;
}
pub fn settle(store: *assistant.Store, intent: Settlement) !bool {
    const service = store.authority orelse return true;
    if (intent.source_tab) |source| {
        const current = try capture(store, source, intent.target_tab);
        if (!std.meta.eql(current.source, intent.source) or !std.meta.eql(current.target, intent.target)) return error.BindingChanged;
    }
    var ready = true;
    for ([_]?@import("session_input.zig").Fence{ intent.source, intent.target }) |maybe| if (maybe) |ticket| {
        const state = store.findConversation(ticket.conversation) orelse return error.BindingChanged;
        const agent = service.store.agent(ticket.agent) orelse return error.BindingChanged;
        if (state.closed or state.ended or state.binding_revision != ticket.binding or !state.owner.eql(agent.owner)) return error.BindingChanged;
        if (!try service.quiesceChildren(ticket, intent.operation)) ready = false;
    };
    return ready;
}
pub fn release(store: *assistant.Store, intent: Settlement) void {
    const service = store.authority orelse return;
    for ([_]?@import("session_input.zig").Fence{ intent.source, intent.target }) |maybe| if (maybe) |ticket| service.store.releaseTransition(ticket, intent.operation);
}

/// Reads existing active entries only. An empty store stays empty.
pub fn prepare(store: *assistant.Store, drop: Drop) !Plan {
    if (drop.group == 0 or drop.source == 0 or drop.container == 0 or drop.container == drop.source or (drop.target != null and (drop.target.? == drop.source or drop.target.? == drop.container))) return error.InvalidTabGroupDrop;
    var plan: Plan = .{ .group = drop.group, .container = drop.container };
    if (store.active(tabOwner(drop.source))) |source| {
        if (store.authority) |service| if (service.store.hasBoundChildren(source.conversation_id)) return error.ChildSettlementRequired;
        _ = try identity.advance(source.binding_revision);
        plan.source = .{ .id = source.id, .revision = source.binding_revision, .conversation = source.conversation_id };
    }
    if (drop.target) |target| if (store.active(tabOwner(target))) |state| {
        plan.handoff = try store.prepareHandoff(state.conversation_id, state.owner, state.binding_revision, tabOwner(drop.container));
    };
    return plan;
}

/// The UI prepares and publishes membership without yielding between these
/// operations. All validation precedes cancellation and the allocation-free
/// owner change; source and target histories are never copied or combined.
pub fn commit(store: *assistant.Store, plan: Plan, raw: *anyopaque, stop: *const fn (*anyopaque, Activity) void) !void {
    if (plan.source) |source| {
        const state = store.find(source.id) orelse return error.ConversationNotFound;
        if (store.authority) |service| if (service.store.hasBoundChildren(state.conversation_id)) return error.ChildSettlementRequired;
        if (!state.conversation_id.eql(source.conversation) or state.closed or state.ended or !state.selected or state.binding_revision != source.revision) return error.BindingChanged;
    }
    if (plan.handoff) |handoff| {
        const checked = try store.prepareHandoff(handoff.id, handoff.from, handoff.revision, handoff.to);
        if (!std.meta.eql(checked, handoff)) return error.BindingChanged;
    }
    if (plan.source) |source| stop(raw, source);
    if (plan.handoff) |handoff| try store.commitHandoff(handoff);
    if (plan.source) |source| try store.endActivity(source.id, source.revision);
}

const StopProbe = struct {
    stopped: ?u64 = null,
    fn stop(raw: *anyopaque, activity: Activity) void {
        const self: *StopProbe = @ptrCast(@alignCast(raw));
        self.stopped = activity.id;
    }
};

test "tab grouping existing group ends source activity and preserves separate histories" {
    var store = assistant.Store.init(std.testing.allocator);
    defer store.deinit();
    const a = (try store.create(.{ .tab = 1 })).id;
    store.find(a).?.phase = .running;
    try store.find(a).?.history.append(store.allocator, .{ .user = true, .text = try store.allocator.dupe(u8, "A history") });
    const g = (try store.create(.{ .tab = 90 })).id;
    const group_identity = store.find(g).?.conversation_id;
    try store.find(g).?.history.append(store.allocator, .{ .user = true, .text = try store.allocator.dupe(u8, "G history") });
    const plan = try prepare(&store, .{ .source = 1, .group = 9, .container = 90 });
    var probe: StopProbe = .{};
    try commit(&store, plan, &probe, StopProbe.stop);
    try std.testing.expectEqual(a, probe.stopped.?);
    try std.testing.expect(store.find(a).?.ended and !store.find(a).?.closed and store.find(a).?.listed and !store.find(a).?.selected);
    try std.testing.expectEqual(assistant.Phase.stopped, store.find(a).?.phase);
    try std.testing.expect(store.active(.{ .tab = 1 }) == null);
    try std.testing.expectEqualStrings("A history", store.find(a).?.history.items[0].text);
    try std.testing.expect(store.find(g).?.conversation_id.eql(group_identity));
    try std.testing.expectEqual(@as(usize, 1), store.find(g).?.history.items.len);
    try std.testing.expectEqualStrings("G history", store.find(g).?.history.items[0].text);
    const welcome_id = (try store.get(.{ .tab = 1 })).id;
    try std.testing.expect(welcome_id != a);
    try std.testing.expect(!store.select(a));
    try std.testing.expectEqual(welcome_id, store.active(.{ .tab = 1 }).?.id);
}

test "tab grouping new group hands off target identity draft controls and history while stopping source" {
    var store = assistant.Store.init(std.testing.allocator);
    defer store.deinit();
    const a = (try store.create(.{ .tab = 1 })).id;
    const b = (try store.create(.{ .tab = 2 })).id;
    const target = store.find(b).?;
    const conversation = target.conversation_id;
    target.draft = try store.allocator.dupe(u8, "B draft");
    try target.controls.setModel(store.allocator, .{ .provider_id = "provider", .model_id = "model" });
    try target.history.append(store.allocator, .{ .user = true, .text = try store.allocator.dupe(u8, "B history") });
    const history_ptr = target.history.items.ptr;
    const plan = try prepare(&store, .{ .source = 1, .target = 2, .group = 9, .container = 90 });
    var probe: StopProbe = .{};
    try commit(&store, plan, &probe, StopProbe.stop);
    try std.testing.expectEqual(a, probe.stopped.?);
    const moved = store.active(.{ .tab = 90 }).?;
    try std.testing.expectEqual(b, moved.id);
    try std.testing.expect(moved.conversation_id.eql(conversation));
    try std.testing.expectEqual(history_ptr, moved.history.items.ptr);
    try std.testing.expectEqualStrings("B history", moved.history.items[0].text);
    try std.testing.expectEqualStrings("B draft", moved.draft.?);
    try std.testing.expectEqualStrings("model", moved.controls.model.?.model_id);
    try std.testing.expectEqual(@as(u64, 2), moved.binding_revision);
    try std.testing.expect(store.find(a).?.ended);
    try std.testing.expect(store.active(.{ .tab = 2 }) == null);
}

test "tab grouping absent assistants starts no activity and leaves store empty" {
    var store = assistant.Store.init(std.testing.allocator);
    defer store.deinit();
    var probe: StopProbe = .{};
    const plan = try prepare(&store, .{ .source = 1, .target = 2, .group = 9, .container = 90 });
    try commit(&store, plan, &probe, StopProbe.stop);
    try std.testing.expect(probe.stopped == null);
    try std.testing.expectEqual(@as(usize, 0), store.states.items.len);
}

test "tab grouping empty welcomes need no runtime settlement but newly bound conversations invalidate capture" {
    const a = std.testing.allocator;
    var service = @import("session_runtime.zig").Service.init(a);
    defer service.deinit();
    var store = assistant.Store.init(a);
    defer store.deinit();
    store.authority = &service;
    _ = try store.get(.{ .tab = 1 });
    _ = try store.get(.{ .tab = 2 });
    const intent = try capture(&store, 1, 2);
    try std.testing.expect(intent.source == null and intent.target == null);
    try std.testing.expect(try settle(&store, intent));
    const agent = try service.store.attach(.{ .tab = 2 });
    const ticket = try service.store.create(agent.id);
    store.active(.{ .tab = 2 }).?.conversation_id = ticket.conversation;
    store.active(.{ .tab = 2 }).?.binding_revision = ticket.binding;
    try std.testing.expectError(error.BindingChanged, settle(&store, intent));
    const bound = try capture(&store, 1, 2);
    try std.testing.expect(bound.target.?.eql(ticket));
    try std.testing.expect(try settle(&store, bound));
}

test "tab grouping into a container tab that already has a conversation is a binding conflict" {
    var store = assistant.Store.init(std.testing.allocator);
    defer store.deinit();
    _ = try store.create(.{ .tab = 2 });
    _ = try store.create(.{ .tab = 90 });
    try std.testing.expectError(error.BindingConflict, prepare(&store, .{ .source = 1, .target = 2, .group = 9, .container = 90 }));
    // 只读的旧归属与非法的容器都不能作为交接目标。
    try std.testing.expectError(error.InvalidTabGroupDrop, prepare(&store, .{ .source = 1, .target = 2, .group = 9, .container = 2 }));
}
