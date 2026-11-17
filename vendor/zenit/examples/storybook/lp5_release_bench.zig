//! LP5 release budget workloads. The runner installs this identical harness in
//! both source snapshots; no preview/template release option is enabled.
const std = @import("std");
const ui = @import("ui");
const v = ui.view;
const samples = 51;
const p95_index = (samples * 95 + 99) / 100 - 1;
const warmups = 5;
const updates = 20;
const fixture = @import("_lp5_release.yix.zig");
const Scenario = enum { branches_1000, for_10000, slots_1000, storybook_full, portals_200, component_for_1000 };
const Result = struct {
    scenario: Scenario,
    unmount_samples_ns: [samples]u64,
    unmount_p50_ns: u64,
    unmount_p95_ns: u64,
    mount_samples_ns: [samples]u64,
    update_samples_ns: [samples]u64,
    incremental_samples_ns: [samples]u64,
    event_samples_ns: [samples]u64,
    mount_p50_ns: u64,
    mount_p95_ns: u64,
    incremental_p50_ns: u64,
    incremental_p95_ns: u64,
    update_p50_ns: u64,
    update_p95_ns: u64,
    event_p50_ns: u64,
    event_p95_ns: u64,
    // Retired instructions of the same regions. The budget takes each phase's minimum: every
    // sample repeats identical work on a fresh Cx, and what varies between samples (interrupts,
    // page faults and other kernel work charged to the thread) only ever adds instructions. Wall
    // time moves with core type, clock and host load far beyond the 5% budget (same-binary A/A up
    // to +24%), and instruction p50/p95 still carry that kernel noise (A/A up to 9% / 22%).
    unmount_samples_instr: [samples]u64,
    mount_samples_instr: [samples]u64,
    update_samples_instr: [samples]u64,
    incremental_samples_instr: [samples]u64,
    event_samples_instr: [samples]u64,
    unmount_p50_instr: u64,
    unmount_p95_instr: u64,
    mount_p50_instr: u64,
    mount_p95_instr: u64,
    incremental_p50_instr: u64,
    incremental_p95_instr: u64,
    update_p50_instr: u64,
    update_p95_instr: u64,
    event_p50_instr: u64,
    event_p95_instr: u64,
    unmount_min_instr: u64,
    mount_min_instr: u64,
    incremental_min_instr: u64,
    update_min_instr: u64,
    event_min_instr: u64,
    peak_requested_bytes: usize,
    allocations: usize,
    residual_bytes: usize,
    nodes: usize,
};
/// Retired instructions of the calling thread (Apple silicon PMC). Declared here rather than
/// imported so the harness builds unchanged against any baseline snapshot.
extern "c" fn thread_selfcounts(kind: c_int, buf: *[2]u64, nbytes: usize) c_int;
fn instructions() u64 {
    var counts: [2]u64 = .{ 0, 0 };
    if (thread_selfcounts(1, &counts, @sizeOf([2]u64)) != 0) return 0;
    return counts[0];
}
const Mark = struct { ns: i96, instr: u64 };
const Cost = struct {
    ns: u64 = 0,
    instr: u64 = 0,
    fn add(self: *Cost, other: Cost) void {
        self.ns += other.ns;
        self.instr += other.instr;
    }
    fn div(self: Cost, n: u64) Cost {
        return .{ .ns = self.ns / n, .instr = self.instr / n };
    }
};
fn now(io: std.Io) Mark {
    return .{ .ns = std.Io.Clock.awake.now(io).nanoseconds, .instr = instructions() };
}
fn elapsed(io: std.Io, start: Mark) Cost {
    const end = now(io);
    return .{ .ns = @intCast(end.ns - start.ns), .instr = end.instr -| start.instr };
}
fn countText(node: *ui.Node, expected: []const u8) usize {
    var count: usize = 0;
    if (node.getText()) |text| count += @intFromBool(std.mem.eql(u8, text.content, expected));
    for (node.children.items) |child| count += countText(child, expected);
    return count;
}
// The component root must carry an actual behavior instance; box/text rows
// would never exercise For's RootLease. Validate each checkbox's settled state.
fn validateComponents(node: *ui.Node, label: []const u8, checked: bool, require_lease: bool) !usize {
    var count: usize = 0;
    if (node.behavior.interaction.a11y) |ax| {
        if (ax.role == .checkbox and countText(node, label) == 1) {
            if (ax.checked != checked) return error.BenchmarkComponentUpdateMissing;
            const instance = v.componentInstance(node) orelse return error.BenchmarkComponentRootMissing;
            if (require_lease and instance.leases == null) return error.BenchmarkLeaseMissing;
            count += 1;
        }
    }
    for (node.children.items) |child| count += try validateComponents(child, label, checked, require_lease);
    return count;
}
fn componentRows(scope: *ui.Scope, cx: *ui.Cx, items: anytype, toggle: *ui.Signal(bool)) !*ui.Node {
    const root = try v.render(scope, cx, v.col(.{}, .{}));
    _ = try ui.control_flow.ForRegion(u32, *ui.Signal(bool), .{
        .key_fn = struct {
            fn key(item: u32) u64 {
                return item;
            }
        }.key,
        .render_fn = struct {
            fn row(checked: *ui.Signal(bool), s: *ui.Scope, c: *ui.Cx, sink: v.Sink, _: u32, _: usize) anyerror!void {
                try v.emit(s, c, sink, ui.widgets.Checkbox(.{ .label = "component-row", .checked = checked }));
            }
        }.row,
    }).mount(scope, cx, .{ .parent = root }, .{ .signal = items }, toggle);
    return root;
}
fn validate(scenario: Scenario, root: *ui.Node, cx: *ui.Cx, shown: bool, mode: fixture.Mode, rows: usize) !void {
    switch (scenario) {
        .branches_1000 => {
            if (countText(root, if (shown) "shown" else "hidden") != 1000 or
                countText(root, if (shown) "hidden" else "shown") != 0 or
                countText(root, if (mode == .a) "alpha" else "beta") != 1000)
                return error.BenchmarkBranchTransitionMissing;
        },
        .for_10000 => if (countText(root, "row") != rows) return error.BenchmarkForTransitionMissing,
        .slots_1000 => if (countText(root, "header") != 1000 or countText(root, "body") != 1000 or countText(root, "footer") != 1000) return error.BenchmarkSlotMissing,
        .portals_200 => {
            const portal = cx.popover_portal_root orelse return error.BenchmarkPortalMissing;
            // c5c37769 uses Link/follow instead of leases for these roots.
            if (try validateComponents(portal, "portal", shown, false) != 200) return error.BenchmarkPortalMissing;
        },
        .component_for_1000 => if (try validateComponents(root, "component-row", shown, true) != rows) return error.BenchmarkForTransitionMissing,
        .storybook_full => if (root.children.items.len == 0) return error.BenchmarkStorybookMissing,
    }
}
/// Chronological samples, one array per unit (reported before any sorting).
const Split = struct { ns: [samples]u64, instr: [samples]u64 };
fn split(costs: [samples]Cost) Split {
    var out: Split = undefined;
    for (costs, 0..) |c, i| {
        out.ns[i] = c.ns;
        out.instr[i] = c.instr;
    }
    return out;
}
fn percentile(chronological: [samples]u64, index: usize) u64 {
    var values = chronological;
    std.mem.sort(u64, &values, {}, std.sort.asc(u64));
    return values[index];
}
pub fn run(init: std.process.Init, comptime mountStorybook: anytype) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const parent = gpa.allocator();
    var results: [std.meta.tags(Scenario).len]Result = undefined;
    var ids: [10000]u32 = undefined;
    for (&ids, 0..) |*id, index| id.* = @intCast(index);
    inline for (std.meta.tags(Scenario), 0..) |scenario, si| {
        var unmount_times: [samples]Cost = undefined;
        var mount_times: [samples]Cost = undefined;
        var incremental: [samples]Cost = @splat(.{});
        var update_times: [samples]Cost = undefined;
        var event_times: [samples]Cost = undefined;
        var peak: usize = 0;
        var allocations: usize = 0;
        var nodes: usize = 0;
        for (0..samples + warmups) |sample| {
            var memory: ui.view.template.MeasurementAllocator = .{ .parent = parent };
            const a = memory.allocator();
            const cx = try ui.Cx.init(a, init.io);
            errdefer cx.deinit();
            const scope = try ui.Scope.init(a, null, cx.owner);
            cx.root_scope = scope;
            const toggle = try scope.createSignal(bool, false);
            const items = try scope.createSignal([]const u32, &.{});
            const mode = try scope.createSignal(fixture.Mode, .a);
            const host = try v.render(scope, cx, v.col(.{}, .{}));
            cx.root = host;
            const control_errors = ui.control_flow.control_flow_error_count;
            const handler_errors = ui.on.handler_error_count;
            const started = now(init.io);
            const root = switch (scenario) {
                .branches_1000, .slots_1000 => wall: {
                    const wall = try v.render(scope, cx, v.col(.{}, .{}));
                    for (0..1000) |_| {
                        const child = if (scenario == .branches_1000)
                            try v.render(scope, cx, fixture.Branches(.{ .shown = toggle, .mode = mode }))
                        else
                            try v.render(scope, cx, fixture.Slots(.{}));
                        try wall.appendChild(a, child);
                    }
                    break :wall wall;
                },
                .portals_200 => portals: {
                    const wall = try v.render(scope, cx, v.col(.{}, .{}));
                    for (0..200) |_| try v.mount(scope, cx, wall, .{
                        v.portal(ui.widgets.Checkbox(.{ .label = "portal", .checked = toggle })),
                    });
                    break :portals wall;
                },
                .component_for_1000 => try componentRows(scope, cx, items, toggle),
                .storybook_full => try mountStorybook(cx, scope),
                .for_10000 => try v.render(scope, cx, fixture.Rows(.{ .items = items })),
            };
            try host.appendChild(a, root);
            const hot = try ui.widgets.Checkbox(.{ .label = "hot-path", .checked = toggle }).mount(scope, cx);
            try root.appendChild(a, hot);
            const incremental_start = now(init.io);
            const row_count: usize = if (scenario == .component_for_1000) 1000 else 10000;
            if (scenario == .for_10000 or scenario == .component_for_1000) items.set(ids[0..row_count]);
            const incremental_cost = elapsed(init.io, incremental_start);
            const mount_cost = elapsed(init.io, started);
            try validate(scenario, root, cx, toggle.peek(), mode.peek(), row_count);
            var update_cost: Cost = .{};
            for (0..updates) |index| {
                const update_start = now(init.io);
                toggle.set(index % 2 == 0);
                if (scenario == .branches_1000) mode.set(if (index % 2 == 0) .b else .a);
                // Alternate deletion/reinsertion of 100 keyed rows. Existing
                // 9,900 rows must remain; this hits incremental row creation.
                if (scenario == .for_10000 or scenario == .component_for_1000) items.set(ids[0 .. row_count - (if (index % 2 == 0) @as(usize, 100) else 0)]);
                update_cost.add(elapsed(init.io, update_start));
                // Validation is outside the timed region; failed/skipped work
                // cannot be accepted as a performance improvement.
                try validate(scenario, root, cx, toggle.peek(), mode.peek(), row_count - (if (index % 2 == 0) @as(usize, 100) else 0));
            }
            const handler = hot.behavior.events.on_click orelse return error.BenchmarkHandlerMissing;
            var event_cost: Cost = .{};
            for (0..updates) |_| {
                const event_start = now(init.io);
                cx.owner.beginReactiveCallback();
                handler.callback(handler.context);
                cx.owner.endReactiveCallback();
                event_cost.add(elapsed(init.io, event_start));
                try validate(scenario, root, cx, toggle.peek(), mode.peek(), row_count);
            }
            if (ui.control_flow.control_flow_error_count != control_errors or ui.on.handler_error_count != handler_errors)
                return error.BenchmarkRuntimeFailure;
            if (sample >= warmups) {
                const index = sample - warmups;
                mount_times[index] = mount_cost;
                incremental[index] = incremental_cost;
                update_times[index] = update_cost.div(updates);
                event_times[index] = event_cost.div(updates);
                peak = @max(peak, memory.peak_bytes);
                allocations = @max(allocations, memory.allocations);
                nodes = cx.world.elements.count();
            }
            const unmount_start = now(init.io);
            cx.deinit();
            const unmount_cost = elapsed(init.io, unmount_start);
            if (sample >= warmups) unmount_times[sample - warmups] = unmount_cost;
            if (memory.live_bytes != 0) return error.BenchmarkResidualAllocation;
        }
        const unmount = split(unmount_times);
        const mount = split(mount_times);
        const inc = split(incremental);
        const update = split(update_times);
        const event = split(event_times);
        if (mount.instr[0] == 0) return error.InstructionCounterUnavailable;
        results[si] = .{
            .scenario = scenario,
            .unmount_samples_ns = unmount.ns,
            .unmount_p50_ns = percentile(unmount.ns, samples / 2),
            .unmount_p95_ns = percentile(unmount.ns, p95_index),
            .mount_samples_ns = mount.ns,
            .update_samples_ns = update.ns,
            .incremental_samples_ns = inc.ns,
            .event_samples_ns = event.ns,
            .mount_p50_ns = percentile(mount.ns, samples / 2),
            .mount_p95_ns = percentile(mount.ns, p95_index),
            .incremental_p50_ns = percentile(inc.ns, samples / 2),
            .incremental_p95_ns = percentile(inc.ns, p95_index),
            .update_p50_ns = percentile(update.ns, samples / 2),
            .update_p95_ns = percentile(update.ns, p95_index),
            .event_p50_ns = percentile(event.ns, samples / 2),
            .event_p95_ns = percentile(event.ns, p95_index),
            .unmount_samples_instr = unmount.instr,
            .mount_samples_instr = mount.instr,
            .update_samples_instr = update.instr,
            .incremental_samples_instr = inc.instr,
            .event_samples_instr = event.instr,
            .unmount_p50_instr = percentile(unmount.instr, samples / 2),
            .unmount_p95_instr = percentile(unmount.instr, p95_index),
            .mount_p50_instr = percentile(mount.instr, samples / 2),
            .mount_p95_instr = percentile(mount.instr, p95_index),
            .incremental_p50_instr = percentile(inc.instr, samples / 2),
            .incremental_p95_instr = percentile(inc.instr, p95_index),
            .update_p50_instr = percentile(update.instr, samples / 2),
            .update_p95_instr = percentile(update.instr, p95_index),
            .event_p50_instr = percentile(event.instr, samples / 2),
            .event_p95_instr = percentile(event.instr, p95_index),
            .unmount_min_instr = percentile(unmount.instr, 0),
            .mount_min_instr = percentile(mount.instr, 0),
            .incremental_min_instr = percentile(inc.instr, 0),
            .update_min_instr = percentile(update.instr, 0),
            .event_min_instr = percentile(event.instr, 0),
            .peak_requested_bytes = peak,
            .allocations = allocations,
            .residual_bytes = 0,
            .nodes = nodes,
        };
    }
    const json = try std.json.Stringify.valueAlloc(parent, .{ .samples = samples, .warmups = warmups, .updates_per_sample = updates, .max_rss_bytes = std.posix.getrusage(0).maxrss, .renderer = "none", .allocator = "CountingAllocator(DebugAllocator)", .results = results }, .{});
    defer parent.free(json);
    try std.Io.File.stdout().writeStreamingAll(init.io, json);
    try std.Io.File.stdout().writeStreamingAll(init.io, "\n");
}
