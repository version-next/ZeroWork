//! 只读回放表面（PLUGIN_ARCH_PLAN 5.2 PL4b H2）：会话记录卡片的详情区嵌入它，跨 feature 只经
//! `features/terminal/mod.zig` 的导出。
//!
//! 它就是一个处于归档模式的终端视图（没有 worker、没有传输凭据、没有输入客户端）：选择、搜索、Esc、
//! 回放条（`terminal.history.{card,title,track,position,notice}`）与拖动跳转都由终端视图自己处理。
//! 原先由 `Workspace.openArchivedContent` 为归档 tab 建的同一个视图，移到这里由卡片持有。
//!
//! **接口冻结**（H2 退出标准）：`create` / `terminal` / `load` / `root` / `seek` / `destroy` 的签名写进
//! 下面的契约单测（构造、挂载、跳转、卸载）；改动它必须同时改这条单测，并在提交说明里写明。
const std = @import("std");
const ui = @import("ui");
const TerminalViewNode = @import("terminal_view.zig").TerminalViewNode;
const Timeline = @import("../../history/mod.zig").Timeline;
const Reading = @import("../../history/mod.zig").ReadingModel;

pub const ReplaySurface = struct {
    cx: *ui.Cx,
    /// 地址固定：终端视图把自身指针交给事件与回放条，所以表面只在堆上创建。
    view: TerminalViewNode,
    loaded: bool = false,

    /// 构造一个未挂载的终端视图。调用方随后经 `terminal()` 套用主题、排版等显示设置，再 `load`。
    pub fn create(cx: *ui.Cx) !*ReplaySurface {
        const self = try cx.allocator.create(ReplaySurface);
        errdefer cx.allocator.destroy(self);
        self.* = .{ .cx = cx, .view = try TerminalViewNode.mount(cx) };
        return self;
    }

    pub fn terminal(self: *ReplaySurface) *TerminalViewNode {
        return &self.view;
    }

    pub fn root(self: *const ReplaySurface) *ui.Node {
        return self.view.root;
    }

    /// 时间线与阅读模型移进表面（调用方的时间线随之清空、阅读模型置空），进入只读回放并打开回放条。
    pub fn load(self: *ReplaySurface, scope: *ui.Scope, timeline: *Timeline, reading: *?Reading) !void {
        if (self.loaded) return error.ReplayAlreadyLoaded;
        if (timeline.frames.items.len == 0) return error.EmptyRecording;
        try self.view.attachSearch(scope);
        self.view.history.deinit();
        self.view.history = timeline.*;
        timeline.* = Timeline.init(timeline.allocator, timeline.limit);
        self.view.bindArchived();
        if (reading.*) |prepared| {
            self.view.history_reading = prepared;
            reading.* = null;
        }
        self.loaded = true;
        _ = self.view.openHistory();
    }

    /// 回放条的跳转（0 = 开头，1 = 结尾）。
    pub fn seek(self: *ReplaySurface, fraction: f32) void {
        self.view.seekHistoryTo(fraction);
    }

    /// 卸载并释放：从父节点摘下、释放终端缓冲与节点。
    pub fn destroy(self: *ReplaySurface) void {
        const cx = self.cx;
        if (self.view.root.parent) |parent| cx.detachChild(parent, self.view.root);
        self.view.clearPendingPaste();
        self.view.releaseBuffers(cx);
        cx.destroyDetached(self.view.root);
        cx.allocator.destroy(self);
    }
};

test "replay surface contract: construct, mount, seek and unmount a read-only recording" {
    const a = std.testing.allocator;
    const cast = "{\"version\":2,\"width\":12,\"height\":2}\n" ++
        "[0,\"o\",\"first\\r\\n\"]\n" ++
        "[1,\"o\",\"second\\r\\n\"]\n" ++
        "[2,\"o\",\"third\"]\n";
    var timeline = try @import("../../history/mod.zig").loadCast(a, cast);
    defer timeline.deinit();
    var reading: ?Reading = try Reading.init(a, &timeline);
    defer if (reading) |*value| value.deinit();
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(600, 200);
    const host = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .column }, .{});
    cx.root = host;
    const scope = try ui.Scope.init(a, null, cx.owner);
    defer scope.dispose();

    // 构造
    const surface = try ReplaySurface.create(cx);
    var destroyed = false;
    defer if (!destroyed) surface.destroy();
    // 挂载：时间线与阅读模型移进表面
    try surface.load(scope, &timeline, &reading);
    try std.testing.expect(timeline.frames.items.len == 0 and reading == null);
    try std.testing.expect(surface.terminal().archive_read_only and surface.terminal().history.selected != null);
    try host.appendChild(cx.allocator, surface.root());
    _ = cx.render();
    try std.testing.expectError(error.ReplayAlreadyLoaded, surface.load(scope, &timeline, &reading));
    // 跳转
    surface.seek(1);
    const reading_model = &surface.terminal().history_reading.?;
    try std.testing.expectEqual(reading_model.maximum, reading_model.offset);
    surface.seek(0);
    try std.testing.expect(reading_model.offset <= reading_model.maximum);
    // 卸载（宿主上可能还留着搜索栏统一关闭按钮的原生 Tooltip 浮层，它归 `scope` 所有，随作用域释放；
    // 这里只核对表面本身已经摘下）。
    const surface_root = surface.root();
    surface.destroy();
    destroyed = true;
    for (host.children.items) |child| try std.testing.expect(child != surface_root);
}
