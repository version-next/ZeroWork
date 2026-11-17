//! Headless benchmark compiled only by -Dlp3b-measure. Uses the full Storybook
//! mount, real component wall and a 10,000-row reactive For of Yix Checkboxes.
const std = @import("std");
const ui = @import("ui");
const v = ui.view;
const samples = 11;
const warmups = 2;
const updates = 1000;
const Scenario = enum { component_wall, for_10000, storybook_full };
const Result = struct {
    scenario: Scenario,
    mount_p50_ns: u64,
    mount_p95_ns: u64,
    incremental_p50_ns: u64,
    update_p50_ns: u64,
    update_p95_ns: u64,
    event_p50_ns: u64,
    event_p95_ns: u64,
    peak_requested_bytes: usize,
    allocations: usize,
    residual_bytes: usize,
    nodes: usize,
};
fn now(io: std.Io) i96 {
    return std.Io.Clock.awake.now(io).nanoseconds;
}
fn elapsed(io: std.Io, start: i96) u64 {
    return @intCast(now(io) - start);
}
fn row(_: u32) @TypeOf(ui.widgets.Checkbox(.{})) {
    return ui.widgets.Checkbox(.{ .label = "row" });
}
fn key(id: u32) u64 {
    return id;
}
fn percentile(values: *[samples]u64, index: usize) u64 {
    std.mem.sort(u64, values, {}, std.sort.asc(u64));
    return values[index];
}
pub fn run(init: std.process.Init, comptime mountStorybook: anytype) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const parent = gpa.allocator();
    var results: [3]Result = undefined;
    var ids: [10000]u32 = undefined;
    for (&ids, 0..) |*id, index| id.* = @intCast(index);
    inline for (std.meta.tags(Scenario), 0..) |scenario, si| {
        var mount_times: [samples]u64 = undefined;
        var incremental: [samples]u64 = @splat(0);
        var update_times: [samples]u64 = undefined;
        var event_times: [samples]u64 = undefined;
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
            const host = try v.render(scope, cx, v.col(.{}, .{}));
            cx.root = host;
            const started = now(init.io);
            const root = switch (scenario) {
                .component_wall => try @import("component_wall.zig").build(scope, cx),
                .storybook_full => try mountStorybook(cx, scope),
                .for_10000 => try v.render(scope, cx, v.col(.{}, .{v.each(items, key, row)})),
            };
            try host.appendChild(a, root);
            const hot = try ui.widgets.Checkbox(.{ .label = "hot-path", .checked = toggle }).mount(scope, cx);
            try root.appendChild(a, hot);
            const incremental_start = now(init.io);
            if (scenario == .for_10000) items.set(&ids);
            const incremental_ns = elapsed(init.io, incremental_start);
            const mount_ns = elapsed(init.io, started);
            const update_start = now(init.io);
            for (0..updates) |index| toggle.set(index % 2 == 0);
            const update_ns = elapsed(init.io, update_start) / updates;
            const handler = hot.behavior.events.on_click orelse return error.BenchmarkHandlerMissing;
            const event_start = now(init.io);
            for (0..updates) |_| {
                cx.owner.beginReactiveCallback();
                handler.callback(handler.context);
                cx.owner.endReactiveCallback();
            }
            const event_ns = elapsed(init.io, event_start) / updates;
            if (sample >= warmups) {
                const index = sample - warmups;
                mount_times[index] = mount_ns;
                incremental[index] = incremental_ns;
                update_times[index] = update_ns;
                event_times[index] = event_ns;
                peak = @max(peak, memory.peak_bytes);
                allocations = @max(allocations, memory.allocations);
                nodes = cx.world.elements.count();
            }
            cx.deinit();
            if (memory.live_bytes != 0) return error.BenchmarkResidualAllocation;
        }
        results[si] = .{
            .scenario = scenario,
            .mount_p50_ns = percentile(&mount_times, 5),
            .mount_p95_ns = percentile(&mount_times, 10),
            .incremental_p50_ns = percentile(&incremental, 5),
            .update_p50_ns = percentile(&update_times, 5),
            .update_p95_ns = percentile(&update_times, 10),
            .event_p50_ns = percentile(&event_times, 5),
            .event_p95_ns = percentile(&event_times, 10),
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
