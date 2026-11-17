//! mockup-yix_spike — UI 架构 revamp P0 的 Yix 技术验证（结论见 docs/ui-revamp/YIX_SPIKE.md）。
//!
//! 结构：
//!   yix_spike/vm.zig            view-model（V-2/V-3/V-4/V-5 共用）
//!   yix_spike/views.yix         每个 V 项一个组件
//!   yix_spike/parts/*.yix       V-1：子目录组件，用 ../ 引回上层
//!   yix_spike/legacy.zig        V-5：手写旧式命令式面板 + ComponentOf 适配
//!   yix_spike/selfcheck.zig     无窗口自检（YIX_SPIKE_SELFCHECK=1）
//!
//! 用法：
//!   zig build mockup -Dmockup=yix_spike            构建预览
//!   YIX_SPIKE_SELFCHECK=1 zig-out/bin/mockup-yix_spike   跑自检，打印 PASS/FAIL 后退出
const std = @import("std");
const ui = @import("ui");
const views = @import("yix_spike/_views.yix.zig");
const m = @import("yix_spike/vm.zig");
const selfcheck = @import("yix_spike/selfcheck.zig");

pub const window_size = .{ .width = 960, .height = 900 };
pub const title = "mockup-yix_spike";

pub fn mount(cx: *ui.Cx, scope: *ui.Scope) anyerror!*ui.Node {
    if (std.c.getenv("YIX_SPIKE_SELFCHECK") != null) std.process.exit(selfcheck.run(cx.io));
    const vm = try m.ViewModel.init(scope);
    return ui.view.render(scope, cx, ui.view.col(.{ .style = ui.css(.{ .gap = 8 }) }, .{
        views.ChromeHeader(.{}), // V-11（落在 runner 固定的 40pt 旧 titlebar 拖动带里）
        views.ImportPanel(.{ .vm = vm }), // V-1
        views.SelectorPanel(.{ .vm = vm }), // V-2
        views.EventPanel(.{ .vm = vm }), // V-3
        views.DirectPanel(.{ .vm = vm }), // V-4
        views.DirectIf(.{ .vm = vm }),
        views.DirectSwitch(.{ .vm = vm }),
        views.DirectOptional(.{ .vm = vm }),
        views.DirectFor(.{ .vm = vm }),
        views.LegacyHost(.{ .vm = vm }), // V-5
    }));
}
