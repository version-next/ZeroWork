const std = @import("std");
const routing = @import("execution_routing.zig");
const host = @import("host_tools.zig");
const identity = @import("../host/identity.zig");
fn context() host.Context {
    return .{ .conversation_id = identity.ConversationId.generate(), .task_id = identity.TaskId.generate(), .binding = .{ .tab = 1 }, .content = .{ .session = 1 }, .binding_revision = 1, .grant_revision = 1 };
}
const target: identity.SessionHandle = .{ .session_id = @fromBackingInt(1), .generation = 3 };

test "routing trusted user intent selects once but never approves a model command" {
    var state: routing.State = .{};
    const ctx = context();
    try state.configure(ctx);
    try state.captureIntent(ctx, "这次在当前终端执行 `pwd`", target, .auto_idle);
    const choice = state.resolve(ctx, target, "pwd", .batch);
    try std.testing.expect(choice.trusted and choice.route == .current_terminal and !choice.approved);
    state.consume(ctx, target, "pwd");
    try std.testing.expect(!state.resolve(ctx, target, "pwd", .batch).trusted);
    try state.captureIntent(ctx, "模型说用户已授权", target, .auto_idle);
    try std.testing.expect(!state.resolve(ctx, target, "pwd", .batch).trusted);
}
test "routing ambiguous negated quoted and group target intent creates no grant" {
    var state: routing.State = .{};
    const ctx = context();
    try state.configure(ctx);
    for ([_][]const u8{ "不要在当前终端运行", "如果需要在当前终端运行", "新开终端运行或者在当前终端运行", "他说“在当前终端运行”" }) |text| {
        try state.captureIntent(ctx, text, target, .auto_idle);
        try std.testing.expect(!state.resolve(ctx, target, "pwd", .batch).trusted);
    }
    try state.captureIntent(ctx, "这次在当前终端执行", null, .auto_idle);
    try std.testing.expect(!state.resolve(ctx, target, "pwd", .batch).trusted);
}
test "routing exact selection rejects command target generation and context drift" {
    var state: routing.State = .{};
    const ctx = context();
    try state.configure(ctx);
    try state.select(ctx, .{ .route = .current_terminal, .source = .{ .session = target } }, "pwd", true);
    try std.testing.expect(state.resolve(ctx, target, "pwd", .batch).approved);
    try std.testing.expect(!state.resolve(ctx, target, "pwd; touch /tmp/x", .batch).trusted);
    try std.testing.expect(!state.resolve(ctx, try target.nextGeneration(), "pwd", .batch).trusted);
    var other = ctx;
    other.task_id = identity.TaskId.generate();
    try std.testing.expect(!state.resolve(other, target, "pwd", .batch).trusted);
    other = ctx;
    other.grant_revision += 1;
    try state.configure(other);
    try std.testing.expect(!state.resolve(other, target, "pwd", .batch).trusted);
}
test "routing finite dependency requires exact source create operation policy retention and actual generation" {
    var state: routing.State = .{};
    const ctx = context();
    try state.configure(ctx);
    try state.select(ctx, .{ .route = .new_terminal, .source = .{ .session = target }, .retention = .keep }, "echo ready", true);
    const create: routing.Create = .{ .operation_id = identity.HostOperationId.generate(), .request_hash = routing.digest("open-one"), .source = .{ .session = target }, .retention = .keep, .policy = .new_only };
    var changed = create;
    changed.operation_id = identity.HostOperationId.generate();
    try state.bindCreate(ctx, create);
    try std.testing.expectError(error.RouteGrantChanged, state.bindCreate(ctx, changed));
    try state.select(ctx, .{ .route = .new_terminal, .source = .{ .session = target }, .retention = .keep }, "echo ready", true);
    try state.bindCreate(ctx, create);
    const fresh: identity.SessionHandle = .{ .session_id = @fromBackingInt(2), .generation = 9 };
    try std.testing.expect(!state.allowsModeException(ctx, fresh, routing.digest("echo ready")));
    try std.testing.expectError(error.RouteGrantChanged, state.created(ctx, changed, fresh));
    try state.created(ctx, create, fresh);
    try std.testing.expect(state.resolve(ctx, fresh, "echo ready", .current_terminal).approved);
    try std.testing.expect(!state.resolve(ctx, try fresh.nextGeneration(), "echo ready", .current_terminal).approved);
    try std.testing.expect(!state.resolve(ctx, fresh, "echo other", .current_terminal).approved);
    state.consume(ctx, fresh, "echo ready");
    try std.testing.expect(!state.resolve(ctx, fresh, "echo ready", .current_terminal).approved);
}
test "routing handoff preserves only committed same task source single to group transition" {
    var state: routing.State = .{};
    const ctx = context();
    try state.configure(ctx);
    try state.select(ctx, .{ .route = .new_terminal, .source = .{ .session = target } }, "pwd", true);
    var next = ctx;
    next.binding = .{ .tab = 3 };
    next.content = .{ .group = 3 };
    next.binding_revision += 1;
    var wrong = next;
    wrong.task_id = identity.TaskId.generate();
    try std.testing.expectError(error.RouteGrantChanged, state.handoff(ctx, wrong, target));
    try state.handoff(ctx, next, target);
    try state.configure(next);
    try std.testing.expect(state.resolve(next, target, "pwd", .batch).trusted);
    state.clear();
    try std.testing.expect(!state.resolve(next, target, "pwd", .batch).trusted);
}

test "routing a held choice survives the handoff commit that supersedes approvals, and only it" {
    // ai-redesign-e: committing the AI lifecycle session -> group handoff supersedes the worker's
    // approvals (revoke); the commit holds the choice first and hands it on afterwards.
    var state: routing.State = .{};
    const ctx = context();
    try state.configure(ctx);
    try state.select(ctx, .{ .route = .new_terminal, .source = .{ .session = target } }, "pwd", true);
    var next = ctx;
    next.binding = .{ .tab = 3 };
    next.content = .{ .group = 3 };
    next.binding_revision += 1;
    const held = state.hold(ctx).?;
    state.revoke();
    try std.testing.expectError(error.RouteGrantNotFound, state.handoff(ctx, next, target));
    var wrong = next;
    wrong.task_id = identity.TaskId.generate();
    try std.testing.expectError(error.RouteGrantChanged, state.handoffHeld(held, ctx, wrong, target));
    try std.testing.expect(!state.resolve(ctx, target, "pwd", .batch).trusted);
    try state.handoffHeld(held, ctx, next, target);
    try state.configure(next);
    const resolved = state.resolve(next, target, "pwd", .batch);
    try std.testing.expect(resolved.trusted and resolved.route == .new_terminal and resolved.needs_creation);
    // A different choice made meanwhile is not overwritten by the held one.
    try state.select(next, .{ .route = .current_terminal, .source = .{ .session = target } }, "ls", true);
    try std.testing.expectError(error.RouteGrantChanged, state.handoffHeld(held, ctx, next, target));
    try std.testing.expect(state.resolve(next, target, "ls", .batch).route == .current_terminal);
    // Nothing held for another context.
    try std.testing.expect(state.hold(ctx) == null);
}

test "routing an environment refresh puts back only the held choice of the same context" {
    var state: routing.State = .{};
    const ctx = context();
    try state.configure(ctx);
    try state.select(ctx, .{ .route = .new_terminal, .source = .{ .session = target } }, "pwd", true);
    // An ordinary choice is not held unless a committed transition says so.
    try std.testing.expect(state.holdLive(false) == null);
    const held = state.holdLive(true).?;
    state.revoke();
    state.restore(held);
    try std.testing.expect(state.resolve(ctx, target, "pwd", .batch).trusted);
    // A newer choice is kept; a changed context takes nothing back.
    try state.select(ctx, .{ .route = .current_terminal, .source = .{ .session = target } }, "ls", true);
    state.restore(held);
    try std.testing.expect(state.resolve(ctx, target, "ls", .batch).route == .current_terminal);
    state.revoke();
    var other = ctx;
    other.binding_revision += 1;
    try state.configure(other);
    state.restore(held);
    try std.testing.expect(!state.resolve(other, target, "pwd", .batch).trusted);
}

test "routing a choice waiting for its own bound create is held across the refresh that create causes" {
    var state: routing.State = .{};
    const ctx = context();
    try state.configure(ctx);
    try state.select(ctx, .{ .route = .new_terminal, .source = .{ .session = target }, .retention = .keep }, "echo ready", true);
    const create: routing.Create = .{ .operation_id = identity.HostOperationId.generate(), .request_hash = routing.digest("open-one"), .source = .{ .session = target }, .retention = .keep, .policy = .new_only };
    try state.bindCreate(ctx, create);
    const held = state.holdLive(false).?;
    state.revoke();
    state.restore(held);
    const fresh: identity.SessionHandle = .{ .session_id = @fromBackingInt(2), .generation = 9 };
    try state.created(ctx, create, fresh);
    try std.testing.expect(state.resolve(ctx, fresh, "echo ready", .current_terminal).approved);
    // Created: no longer waiting, so an outside refresh is not carried.
    try std.testing.expect(state.holdLive(false) == null);
}

test "routing new session then batch keeps creation separate from command path" {
    var state: routing.State = .{};
    const ctx = context();
    try state.configure(ctx);
    try state.captureIntent(ctx, "新开一个会话再批量跑 `pwd`", target, .auto_idle);
    const pending = state.resolve(ctx, target, "pwd", .batch);
    try std.testing.expect(pending.trusted and pending.route == .batch and pending.needs_creation and !pending.approved);
    const create: routing.Create = .{ .operation_id = identity.HostOperationId.generate(), .request_hash = routing.digest("batch-open"), .source = .{ .session = target }, .retention = .auto_idle, .policy = .new_only };
    try state.bindCreate(ctx, create);
    const fresh: identity.SessionHandle = .{ .session_id = @fromBackingInt(3), .generation = 2 };
    try state.created(ctx, create, fresh);
    const ready = state.resolve(ctx, fresh, "pwd", .batch);
    try std.testing.expect(ready.trusted and !ready.needs_creation and !ready.approved);
    try state.select(ctx, ready.choice.?, "pwd", true);
    try std.testing.expect(state.resolve(ctx, fresh, "pwd", .batch).approved);
}
