//! “尚未配置 AI 服务”就地提示的状态与挂载（视图 `ai_unconfigured.yix`）。宿主在输入门禁里调用 `show` /
//! `hide`；同值重复写不触发任何更新。
const std = @import("std");
const ui = @import("ui");
const IdSpace = @import("../../shared/view/ai_id_space.zig").IdSpace;
const template = @import("_ai_unconfigured.yix.zig");

/// 没有服务提供方 / 没有模型时的标题与说明；其他配置问题沿用错误文案作说明。
pub const missing_title = "尚未配置 AI 服务";
pub const missing_message = "添加服务提供方和模型后即可对话。";
pub const unusable_title = "AI 服务暂不可用";

pub const View = struct {
    root: *ui.Node,
    title: *ui.Signal([]const u8),
    message: *ui.Signal([]const u8),
    shown: *ui.Signal(bool),

    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, on_configure: ui.Handler(void)) !*View {
        const self = try scope.createState(View, .{ .root = undefined, .title = try scope.createText(missing_title, .{}), .message = try scope.createText(missing_message, .{}), .shown = try scope.createSignal(bool, false) });
        self.root = try ui.view.render(scope, cx, template.Unconfigured(.{ .space = IdSpace.of(scope), .title = self.title, .message = self.message, .shown = self.shown, .on_configure = on_configure }));
        return self;
    }

    pub fn show(self: *View, title: []const u8, message: []const u8) void {
        if (!std.mem.eql(u8, self.title.peek(), title)) self.title.set(title);
        if (!std.mem.eql(u8, self.message.peek(), message)) self.message.set(message);
        if (!self.shown.peek()) self.shown.set(true);
    }

    pub fn hide(self: *View) void {
        if (self.shown.peek()) self.shown.set(false);
    }
};

/// 未配置时的引导放在哪里（主会话判定，ai-redesign-c）：对话为空（显示空状态）时只在空状态里引导（“配置模型，开始
/// 对话” + “配置 AI 服务”）；已有对话历史时才在输入区上方放这条原生 Alert。两者不同时出现。
pub const Placement = enum { none, empty_state, alert };
pub fn placement(problem: ?anyerror, empty_state: bool) Placement {
    if (problem == null) return .none;
    return if (empty_state) .empty_state else .alert;
}

/// 没有可用服务的错误（配置缺失）→ “尚未配置 AI 服务”；其余模型配置问题 → “AI 服务暂不可用”。
pub fn isMissing(problem: anyerror) bool {
    return problem == error.MissingProviderConfiguration or problem == error.MissingProvider or problem == error.MissingModel;
}

test "isMissing: provider or model not configured" {
    try std.testing.expect(isMissing(error.MissingProviderConfiguration));
    try std.testing.expect(isMissing(error.MissingModel));
    try std.testing.expect(!isMissing(error.MissingApiKey));
}

test "placement: the empty state guides an empty conversation, the Alert only with history" {
    try std.testing.expectEqual(Placement.none, placement(null, true));
    try std.testing.expectEqual(Placement.none, placement(null, false));
    try std.testing.expectEqual(Placement.empty_state, placement(error.MissingModel, true));
    try std.testing.expectEqual(Placement.alert, placement(error.MissingModel, false));
    try std.testing.expectEqual(Placement.alert, placement(error.MissingApiKey, false));
}
