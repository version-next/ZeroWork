// GENERATED FILE, do not edit: generated from connection_failure.yix; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! 连接失败 / 重试视图（design-r3 稿 1，Pencil RDiob › Hwswl）：会话 tab 内容区里居中的一列（宽 560），
//! 替代连接进度卡片的失败态与等待自动重试态。只用 zenit 原生组件，外观全是默认：
//!
//! - 头部：失败类别图标、主机名、`user@host:port`（等宽）、右侧原生 `W.StatusBadge`（“N 秒后重试 / 已停止重试 / 需要确认”）。
//! - 一句话标题；失败原因是原生 `W.Alert`（error / warning），写明具体地址、端口、用户名。
//! - 只有确实在等一次自动重试时才有重试行：说明文字 + 原生 `W.Progress` 倒计时条；不重试时一行说明为什么。
//! - 主机密钥变更：“已保存的密钥”与“服务器当前提供的密钥”两块指纹（后者用危险色）。
//! - 逐跳连接路径：本机 → 各跳 → 目标，状态用用户能看懂的说法。
//! - 操作行：左“编辑连接”（secondary）“查看日志 / 收起日志”（ghost）；右继续类操作，主按钮在最右
//!   （立即重试 / 重新输入凭据 / “替换主机密钥”用 danger；替换前先弹原生确认框 `W.ConfirmDialog`，规则取
//!   `shared/ui/confirm`：焦点在“取消”，Esc / × / 点遮罩 = 取消）。
//! 文案与状态全部来自 `model/failure_view.zig` 的投影；这里不做判断，只把点击交给 `FailureView.act`。
const ui = @import("ui");
const W = ui.widgets;
const m = @import("../model/failure_view.zig");
const C = @import("failure_controller.zig");
const S = @import("_connection_failure.yss.zig");
const Confirm = @import("../../../../shared/ui/confirm/confirm.zig");

pub const ids = struct {
    pub const root = "connection.progress.failure";
    pub const badge = "connection.progress.failure.badge";
    pub const title = "connection.progress.failure.title";
    pub const alert = "connection.progress.failure.alert";
    pub const retry = "connection.progress.failure.retry";
    pub const retry_bar = "connection.progress.failure.retry.bar";
    pub const hold = "connection.progress.failure.hold";
    pub const saved_key = "connection.progress.failure.key.saved";
    pub const offered_key = "connection.progress.failure.key.offered";
    pub const route = "connection.progress.failure.route";
    pub const hop = "connection.progress.failure.hop";
    pub const logs = "connection.progress.failure.logs";
    pub const edit = "connection.progress.failure.edit";
    pub const logs_toggle = "connection.progress.failure.logs.toggle";
    pub const stop_retry = "connection.progress.failure.stop";
    pub const retry_now = "connection.progress.failure.retry_now";
    pub const credentials = "connection.progress.failure.credentials";
    pub const disconnect = "connection.progress.failure.disconnect";
    pub const trust_key = "connection.progress.failure.trust";
    pub const trust_confirm = "connection.progress.failure.trust.confirm";
    pub const trust_confirm_cancel = "connection.progress.failure.trust.cancel";
    pub const trust_confirm_accept = "connection.progress.failure.trust.accept";
};

const replace_key = Confirm.label(.replace, "主机密钥");
fn trustOpen(vm: *C.FailureView) bool {
    return vm.trust_confirm.get();
}
fn trustConfirmed(vm: *C.FailureView) void {
    vm.trustConfirmed();
}
fn trustCancelled(vm: *C.FailureView) void {
    vm.trust_confirm.set(false);
}

fn send(vm: *C.FailureView, action: C.Action) void {
    vm.act(action);
}
fn headIcon(icon: m.Icon) ui.SvgAsset {
    return switch (icon) {
        .refused, .failed => ui.icons.circle_x,
        .timeout => ui.icons.clock_alert,
        .shield => ui.icons.shield_alert,
    };
}
fn headTone(icon: m.Icon) S.Tone {
    return if (icon == .timeout) .warning else .danger;
}
/// The four tone recipes share variant names; each has its own dimension type.
fn toneOf(comptime T: type, tone: m.Tone) T {
    return switch (tone) {
        .ok => .ok,
        .danger => .danger,
        .warning => .warning,
        .muted => .muted,
    };
}
fn badgeStatus(badge: m.Badge) W.badge.BadgeStatus {
    return switch (badge) {
        .info => .info,
        .success => .success,
        .warning => .warning,
        .@"error" => .@"error",
    };
}
fn alertVariant(warning: bool) W.AlertVariant {
    return if (warning) .warning else .@"error";
}
fn hopIcon(tone: m.Tone) ui.SvgAsset {
    return switch (tone) {
        .ok => ui.icons.check,
        .danger => ui.icons.x,
        .warning => ui.icons.triangle_alert,
        .muted => ui.icons.circle_dashed,
    };
}
fn retryVariant(p: m.Projection) W.ButtonVariant {
    return if (p.primary == .retry_now) .primary else .secondary;
}

fn HopRow(args: anytype) ui.view.ComponentOf(__yix_HopRow) {
    return ui.view.component(__yix_HopRow, ui.reactive.props.coerce(HopRowProps, args));
}
const HopRowProps = struct {
    hop: ui.Source(m.HopRow),
    index: ui.Source(usize),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = HopRow;
    pub const __yix_preview_mount = __yix_HopRow;
};
fn __yix_HopRow(__yix_props: HopRowProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const hop = __yix_props.hop;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .hop = hop, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "HopRow", .receiver = "row", .tokens = "row testId = ids . hop ; style = @static; a11y = . { . role = . listitem , . label = hop . name , . value_text = hop . status } ; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "ids . hop ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . hop_row ", .kind = .style, .literal = null }, .{ .name = "a11y", .tokens = ". { . role = . listitem , . label = hop . name , . value_text = hop . status } ", .kind = .property, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .hop = __yix_view_ctx.hop, }, ui.view.row(.{ .test_id = ids.hop, .style = S.hop_row, .a11y = .{ .role = .listitem, .label = __yix_d1: {
        const __yix_T = @TypeOf(__yix_view_ctx.hop.peek().name);
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .hop = __yix_view_ctx.hop, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.hop.get().name;
        } }.__yix_compute);
    }, .value_text = __yix_d2: {
        const __yix_T = @TypeOf(__yix_view_ctx.hop.peek().status);
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .hop = __yix_view_ctx.hop, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.hop.get().status;
        } }.__yix_compute);
    } }, }, .{
            ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "HopRow", .receiver = "box", .tokens = "box style = S . Marker . of ( . { . tone = toneOf ( S . MarkerTone , hop . tone ) } ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . Marker . of ( . { . tone = toneOf ( S . MarkerTone , hop . tone ) } ) ", .kind = .style, .literal = null }, } }, .{ .hop = __yix_view_ctx.hop, }, ui.view.box(.{ .style = S.Marker.of(.{ .tone = __yix_d3: {
        const __yix_T = @TypeOf(toneOf(S.MarkerTone, __yix_view_ctx.hop.peek().tone));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .hop = __yix_view_ctx.hop, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return toneOf(S.MarkerTone, __yix_ctx.hop.get().tone);
        } }.__yix_compute);
    } }), }, .{
                ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "HopRow", .receiver = "icon", .tokens = "icon style = S . MarkerIcon . of ( . { . tone = toneOf ( S . MarkerIconTone , hop . tone ) } ) ; src = hopIcon ( hop . tone ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . MarkerIcon . of ( . { . tone = toneOf ( S . MarkerIconTone , hop . tone ) } ) ", .kind = .style, .literal = null }, .{ .name = "src", .tokens = "hopIcon ( hop . tone ) ", .kind = .property, .literal = null }, } }, .{ .hop = __yix_view_ctx.hop, }, ui.view.icon(.{ .style = S.MarkerIcon.of(.{ .tone = __yix_d4: {
        const __yix_T = @TypeOf(toneOf(S.MarkerIconTone, __yix_view_ctx.hop.peek().tone));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .hop = __yix_view_ctx.hop, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return toneOf(S.MarkerIconTone, __yix_ctx.hop.get().tone);
        } }.__yix_compute);
    } }), }, __yix_d5: {
        const __yix_T = @TypeOf(hopIcon(__yix_view_ctx.hop.peek().tone));
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ .hop = __yix_view_ctx.hop, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return hopIcon(__yix_ctx.hop.get().tone);
        } }.__yix_compute);
    })),
            })),
            ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "HopRow", .receiver = "col", .tokens = "col style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . hop_text ", .kind = .style, .literal = null }, } }, .{ .hop = __yix_view_ctx.hop, }, ui.view.col(.{ .style = S.hop_text, }, .{
                ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "HopRow", .receiver = "text", .tokens = "text style = @static; hop . name  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . hop_name ", .kind = .style, .literal = null }, } }, .{ .hop = __yix_view_ctx.hop, }, ui.view.text(.{ .style = S.hop_name, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d6: {
        const __yix_T = @TypeOf(__yix_view_ctx.hop.peek().name);
        break :__yix_d6 try __yix_view_scope.derive(__yix_T, .{ .hop = __yix_view_ctx.hop, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.hop.get().name;
        } }.__yix_compute);
    }), ""), .{ __yix_d6: {
        const __yix_T = @TypeOf(__yix_view_ctx.hop.peek().name);
        break :__yix_d6 try __yix_view_scope.derive(__yix_T, .{ .hop = __yix_view_ctx.hop, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.hop.get().name;
        } }.__yix_compute);
    }, }))),
                ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "HopRow", .receiver = "text", .tokens = "text style = @static; hop . address  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . hop_address ", .kind = .style, .literal = null }, } }, .{ .hop = __yix_view_ctx.hop, }, ui.view.text(.{ .style = S.hop_address, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d7: {
        const __yix_T = @TypeOf(__yix_view_ctx.hop.peek().address);
        break :__yix_d7 try __yix_view_scope.derive(__yix_T, .{ .hop = __yix_view_ctx.hop, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.hop.get().address;
        } }.__yix_compute);
    }), ""), .{ __yix_d7: {
        const __yix_T = @TypeOf(__yix_view_ctx.hop.peek().address);
        break :__yix_d7 try __yix_view_scope.derive(__yix_T, .{ .hop = __yix_view_ctx.hop, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.hop.get().address;
        } }.__yix_compute);
    }, }))),
            })),
            ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "HopRow", .receiver = "text", .tokens = "text style = S . HopStatus . of ( . { . tone = toneOf ( S . HopStatusTone , hop . tone ) } ) ; box = S . fixed_box ; hop . status  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . HopStatus . of ( . { . tone = toneOf ( S . HopStatusTone , hop . tone ) } ) ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . fixed_box ", .kind = .property, .literal = null }, } }, .{ .hop = __yix_view_ctx.hop, }, ui.view.text(.{ .style = S.HopStatus.of(.{ .tone = __yix_d8: {
        const __yix_T = @TypeOf(toneOf(S.HopStatusTone, __yix_view_ctx.hop.peek().tone));
        break :__yix_d8 try __yix_view_scope.derive(__yix_T, .{ .hop = __yix_view_ctx.hop, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return toneOf(S.HopStatusTone, __yix_ctx.hop.get().tone);
        } }.__yix_compute);
    } }), .box = S.fixed_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d9: {
        const __yix_T = @TypeOf(__yix_view_ctx.hop.peek().status);
        break :__yix_d9 try __yix_view_scope.derive(__yix_T, .{ .hop = __yix_view_ctx.hop, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.hop.get().status;
        } }.__yix_compute);
    }), ""), .{ __yix_d9: {
        const __yix_T = @TypeOf(__yix_view_ctx.hop.peek().status);
        break :__yix_d9 try __yix_view_scope.derive(__yix_T, .{ .hop = __yix_view_ctx.hop, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.hop.get().status;
        } }.__yix_compute);
    }, }))),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "HopRow";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

pub fn ConnectionFailure(args: anytype) ui.view.ComponentOf(__yix_ConnectionFailure) {
    return ui.view.component(__yix_ConnectionFailure, ui.reactive.props.coerce(ConnectionFailureProps, args));
}
pub const ConnectionFailureProps = struct {
    vm: ui.Source(*C.FailureView),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = ConnectionFailure;
    pub const __yix_preview_mount = __yix_ConnectionFailure;
};
fn __yix_ConnectionFailure(__yix_props: ConnectionFailureProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "box", .tokens = "box testId = ids . root ; style = @static; visible = vm . shown ( ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "ids . root ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . surface ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "vm . shown ( ) ", .kind = .property, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .vm = __yix_view_ctx.vm, }, ui.view.box(.{ .test_id = ids.root, .style = S.surface, .visible = __yix_d1: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().shown());
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().shown();
        } }.__yix_compute);
    }, }, .{
            ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "col", .tokens = "col style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . column ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.col(.{ .style = S.column, }, .{
                ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "row", .tokens = "row style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . header ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.row(.{ .style = S.header, }, .{
                    ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "icon", .tokens = "icon style = S . HeadIcon . of ( . { . tone = headTone ( vm . p ( ) . icon ) } ) ; src = headIcon ( vm . p ( ) . icon ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . HeadIcon . of ( . { . tone = headTone ( vm . p ( ) . icon ) } ) ", .kind = .style, .literal = null }, .{ .name = "src", .tokens = "headIcon ( vm . p ( ) . icon ) ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.icon(.{ .style = S.HeadIcon.of(.{ .tone = __yix_d2: {
        const __yix_T = @TypeOf(headTone(__yix_view_ctx.vm.peek().p().icon));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return headTone(__yix_ctx.vm.get().p().icon);
        } }.__yix_compute);
    } }), }, __yix_d3: {
        const __yix_T = @TypeOf(headIcon(__yix_view_ctx.vm.peek().p().icon));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return headIcon(__yix_ctx.vm.get().p().icon);
        } }.__yix_compute);
    })),
                    ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "text", .tokens = "text style = @static; box = S . name_box ; vm . p ( ) . name  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . name ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . name_box ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.text(.{ .style = S.name, .box = S.name_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d4: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().p().name);
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().p().name;
        } }.__yix_compute);
    }), ""), .{ __yix_d4: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().p().name);
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().p().name;
        } }.__yix_compute);
    }, }))),
                    ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "text", .tokens = "text style = @static; box = S . endpoint_box ; vm . p ( ) . endpoint  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . endpoint ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . endpoint_box ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.text(.{ .style = S.endpoint, .box = S.endpoint_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d5: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().p().endpoint);
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().p().endpoint;
        } }.__yix_compute);
    }), ""), .{ __yix_d5: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().p().endpoint);
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().p().endpoint;
        } }.__yix_compute);
    }, }))),
                    ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "spacer", .tokens = "spacer ", .literal_text = null, .attributes = &.{ } }, .{ }, ui.view.spacer()),
                    ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "W.StatusBadge", .tokens = "< W . StatusBadge testId = { ids . badge } status = { badgeStatus ( vm . p ( ) . badge ) } label = { vm . p ( ) . badge_text } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "ids . badge ", .kind = .property, .literal = null }, .{ .name = "status", .tokens = "badgeStatus ( vm . p ( ) . badge ) ", .kind = .property, .literal = null }, .{ .name = "label", .tokens = "vm . p ( ) . badge_text ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.templateAttrs(.{ .test_id = ids.badge, }, __yix_builder_5997: { try ui.view.previewCheckBuilder(__yix_view_scope, W.StatusBadge); break :__yix_builder_5997 W.StatusBadge(.{ .status = __yix_d6: {
        const __yix_T = if (ui.view.attrType(W.StatusBadge, "status")) |__yix_A| __yix_A else @TypeOf(badgeStatus(__yix_view_ctx.vm.peek().p().badge));
        break :__yix_d6 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return badgeStatus(__yix_ctx.vm.get().p().badge);
        } }.__yix_compute);
    }, .label = __yix_d7: {
        const __yix_T = if (ui.view.attrType(W.StatusBadge, "label")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().p().badge_text);
        break :__yix_d7 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().p().badge_text;
        } }.__yix_compute);
    }, }); })),
                })),
                ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "text", .tokens = "text testId = ids . title ; style = @static; box = S . fill_box ; a11y = . { . role = . heading } ; vm . p ( ) . title  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "ids . title ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . title ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . fill_box ", .kind = .property, .literal = null }, .{ .name = "a11y", .tokens = ". { . role = . heading } ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.text(.{ .test_id = ids.title, .style = S.title, .box = S.fill_box, .a11y = .{ .role = .heading }, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d8: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().p().title);
        break :__yix_d8 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().p().title;
        } }.__yix_compute);
    }), ""), .{ __yix_d8: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().p().title);
        break :__yix_d8 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().p().title;
        } }.__yix_compute);
    }, }))),
                ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "W.Alert", .tokens = "< W . Alert testId = { ids . alert } variant = { alertVariant ( vm . p ( ) . alert_warning ) } title = { vm . p ( ) . alert_title } message = { vm . p ( ) . alert_detail } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "ids . alert ", .kind = .property, .literal = null }, .{ .name = "variant", .tokens = "alertVariant ( vm . p ( ) . alert_warning ) ", .kind = .property, .literal = null }, .{ .name = "title", .tokens = "vm . p ( ) . alert_title ", .kind = .property, .literal = null }, .{ .name = "message", .tokens = "vm . p ( ) . alert_detail ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.templateAttrs(.{ .test_id = ids.alert, }, __yix_builder_6259: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Alert); break :__yix_builder_6259 W.Alert(.{ .variant = __yix_d9: {
        const __yix_T = if (ui.view.attrType(W.Alert, "variant")) |__yix_A| __yix_A else @TypeOf(alertVariant(__yix_view_ctx.vm.peek().p().alert_warning));
        break :__yix_d9 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return alertVariant(__yix_ctx.vm.get().p().alert_warning);
        } }.__yix_compute);
    }, .title = __yix_d10: {
        const __yix_T = if (ui.view.attrType(W.Alert, "title")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().p().alert_title);
        break :__yix_d10 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().p().alert_title;
        } }.__yix_compute);
    }, .message = __yix_d11: {
        const __yix_T = if (ui.view.attrType(W.Alert, "message")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().p().alert_detail);
        break :__yix_d11 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().p().alert_detail;
        } }.__yix_compute);
    }, }); })),
                ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "col", .tokens = "col testId = ids . retry ; style = @static; visible = vm . p ( ) . retry_shown ; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "ids . retry ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . retry ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "vm . p ( ) . retry_shown ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.col(.{ .test_id = ids.retry, .style = S.retry, .visible = __yix_d12: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().p().retry_shown);
        break :__yix_d12 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().p().retry_shown;
        } }.__yix_compute);
    }, }, .{
                    ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "row", .tokens = "row style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . note_row ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.row(.{ .style = S.note_row, }, .{
                        ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "icon", .tokens = "icon style = @static; src = ui . icons . refresh_cw ; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . note_icon ", .kind = .style, .literal = null }, .{ .name = "src", .tokens = "ui . icons . refresh_cw ", .kind = .property, .literal = null }, } }, .{ }, ui.view.icon(.{ .style = S.note_icon, }, ui.icons.refresh_cw)),
                        ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "text", .tokens = "text style = @static; box = S . grow_box ; vm . p ( ) . retry_text  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . note ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . grow_box ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.text(.{ .style = S.note, .box = S.grow_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d13: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().p().retry_text);
        break :__yix_d13 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().p().retry_text;
        } }.__yix_compute);
    }), ""), .{ __yix_d13: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().p().retry_text);
        break :__yix_d13 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().p().retry_text;
        } }.__yix_compute);
    }, }))),
                    })),
                    ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "box", .tokens = "box testId = ids . retry_bar ; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "ids . retry_bar ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . bar ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.box(.{ .test_id = ids.retry_bar, .style = S.bar, }, .{
                        ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "W.Progress", .tokens = "< W . Progress value = { vm . p ( ) . retry_percent } height = { 4 } sweep = { . flat } / > ", .literal_text = null, .attributes = &.{ .{ .name = "value", .tokens = "vm . p ( ) . retry_percent ", .kind = .property, .literal = null }, .{ .name = "height", .tokens = "4 ", .kind = .property, .literal = .{ .number = 4 } }, .{ .name = "sweep", .tokens = ". flat ", .kind = .property, .literal = .{ .enum_name = "flat" } }, } }, .{ .vm = __yix_view_ctx.vm, }, __yix_builder_6780: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Progress); break :__yix_builder_6780 W.Progress(.{ .value = __yix_d14: {
        const __yix_T = if (ui.view.attrType(W.Progress, "value")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().p().retry_percent);
        break :__yix_d14 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().p().retry_percent;
        } }.__yix_compute);
    }, .height = 4, .sweep = .flat, }); }),
                    })),
                })),
                ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "row", .tokens = "row testId = ids . hold ; style = @static; visible = vm . holdShown ( ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "ids . hold ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . note_row ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "vm . holdShown ( ) ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.row(.{ .test_id = ids.hold, .style = S.note_row, .visible = __yix_d15: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().holdShown());
        break :__yix_d15 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().holdShown();
        } }.__yix_compute);
    }, }, .{
                    ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "icon", .tokens = "icon style = @static; src = ui . icons . pause ; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . note_icon ", .kind = .style, .literal = null }, .{ .name = "src", .tokens = "ui . icons . pause ", .kind = .property, .literal = null }, } }, .{ }, ui.view.icon(.{ .style = S.note_icon, }, ui.icons.pause)),
                    ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "text", .tokens = "text style = @static; box = S . grow_box ; vm . p ( ) . hold_text  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . note ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . grow_box ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.text(.{ .style = S.note, .box = S.grow_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d16: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().p().hold_text);
        break :__yix_d16 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().p().hold_text;
        } }.__yix_compute);
    }), ""), .{ __yix_d16: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().p().hold_text);
        break :__yix_d16 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().p().hold_text;
        } }.__yix_compute);
    }, }))),
                })),
                ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "col", .tokens = "col style = @static; visible = vm . p ( ) . host_key_shown ; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . keys ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "vm . p ( ) . host_key_shown ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.col(.{ .style = S.keys, .visible = __yix_d17: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().p().host_key_shown);
        break :__yix_d17 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().p().host_key_shown;
        } }.__yix_compute);
    }, }, .{
                    ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "col", .tokens = "col testId = ids . saved_key ; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "ids . saved_key ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . key_block ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.col(.{ .test_id = ids.saved_key, .style = S.key_block, }, .{
                        ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "text", .tokens = "text style = @static; vm . p ( ) . saved_key_title  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . key_title ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.text(.{ .style = S.key_title, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d18: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().p().saved_key_title);
        break :__yix_d18 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().p().saved_key_title;
        } }.__yix_compute);
    }), ""), .{ __yix_d18: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().p().saved_key_title);
        break :__yix_d18 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().p().saved_key_title;
        } }.__yix_compute);
    }, }))),
                        ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "text", .tokens = "text style = @static; box = S . fill_box ; vm . p ( ) . saved_key  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . key_value ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . fill_box ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.text(.{ .style = S.key_value, .box = S.fill_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d19: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().p().saved_key);
        break :__yix_d19 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().p().saved_key;
        } }.__yix_compute);
    }), ""), .{ __yix_d19: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().p().saved_key);
        break :__yix_d19 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().p().saved_key;
        } }.__yix_compute);
    }, }))),
                    })),
                    ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "col", .tokens = "col testId = ids . offered_key ; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "ids . offered_key ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . key_block ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.col(.{ .test_id = ids.offered_key, .style = S.key_block, }, .{
                        ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "text", .tokens = "text style = @static; vm . p ( ) . offered_key_title  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . key_title ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.text(.{ .style = S.key_title, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d20: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().p().offered_key_title);
        break :__yix_d20 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().p().offered_key_title;
        } }.__yix_compute);
    }), ""), .{ __yix_d20: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().p().offered_key_title);
        break :__yix_d20 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().p().offered_key_title;
        } }.__yix_compute);
    }, }))),
                        ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "text", .tokens = "text style = @static; box = S . fill_box ; vm . p ( ) . offered_key  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . key_value_changed ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . fill_box ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.text(.{ .style = S.key_value_changed, .box = S.fill_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d21: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().p().offered_key);
        break :__yix_d21 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().p().offered_key;
        } }.__yix_compute);
    }), ""), .{ __yix_d21: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().p().offered_key);
        break :__yix_d21 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().p().offered_key;
        } }.__yix_compute);
    }, }))),
                    })),
                })),
                ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "col", .tokens = "col testId = ids . route ; style = @static; a11y = . { . role = . list , . label = vm . p ( ) . route } ; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "ids . route ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . route ", .kind = .style, .literal = null }, .{ .name = "a11y", .tokens = ". { . role = . list , . label = vm . p ( ) . route } ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.col(.{ .test_id = ids.route, .style = S.route, .a11y = .{ .role = .list, .label = __yix_d22: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().p().route);
        break :__yix_d22 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().p().route;
        } }.__yix_compute);
    } }, }, .{
                    ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "text", .tokens = "text style = @static; vm . p ( ) . route  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . route_label ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.text(.{ .style = S.route_label, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d23: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().p().route);
        break :__yix_d23 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().p().route;
        } }.__yix_compute);
    }), ""), .{ __yix_d23: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().p().route);
        break :__yix_d23 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().p().route;
        } }.__yix_compute);
    }, }))),
                    ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "control", .tokens = "for ( vm . p ( ) . hops ) | hop , i | < HopRow key = { hop . key } hop = { hop } index = { i } / > " }, .{ .vm = __yix_view_ctx.vm, }, __yix_e1: { const __yix_items_1 = __yix_d1: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().p().hops);
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().p().hops;
        } }.__yix_compute);
    }; break :__yix_e1 ui.view.eachWith(.{ }, __yix_items_1, struct { fn __yix_k(hop: ui.view.yixItem(@TypeOf(__yix_items_1))) u64 { return ui.view.keyOf(hop.key); } }.__yix_k, struct { fn __yix_row(__yix_row_1: anytype, hop: ui.Source(ui.view.yixItem(@TypeOf(__yix_items_1))), i: ui.Source(usize), __yix_scope_1: *ui.Scope, __yix_cx_1: *ui.Cx) anyerror!*ui.Node { _ = __yix_row_1; return ui.view.render(__yix_scope_1, __yix_cx_1, ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure/keyword_for:1", .receiver = "HopRow", .tokens = "< HopRow key = { hop . key } hop = { hop } index = { i } / > ", .literal_text = null, .attributes = &.{ .{ .name = "key", .tokens = "hop . key ", .kind = .property, .literal = null }, .{ .name = "hop", .tokens = "hop ", .kind = .property, .literal = null }, .{ .name = "index", .tokens = "i ", .kind = .property, .literal = null }, } }, .{ .hop = hop, .i = i, }, __yix_builder_27: { try ui.view.previewCheckBuilder(__yix_scope_1, HopRow); break :__yix_builder_27 HopRow(.{ .hop = hop, .index = i, }); })); } }.__yix_row); }),
                })),
                ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "col", .tokens = "col testId = ids . logs ; style = @static; visible = vm . p ( ) . logs_open ; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "ids . logs ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . logs ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "vm . p ( ) . logs_open ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.col(.{ .test_id = ids.logs, .style = S.logs, .visible = __yix_d24: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().p().logs_open);
        break :__yix_d24 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().p().logs_open;
        } }.__yix_compute);
    }, }, .{
                    ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "control", .tokens = "for ( vm . logLines ( ) ) | line | < text style = { S . log_line } box = { S . fill_box } > { line . text } < / text > " }, .{ .vm = __yix_view_ctx.vm, }, __yix_e2: { const __yix_items_2 = __yix_d2: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().logLines());
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().logLines();
        } }.__yix_compute);
    }; break :__yix_e2 ui.view.eachWith(.{ }, __yix_items_2, .id, struct { fn __yix_row(__yix_row_1: anytype, line: ui.Source(ui.view.yixItem(@TypeOf(__yix_items_2))), __yix_scope_1: *ui.Scope, __yix_cx_1: *ui.Cx) anyerror!*ui.Node { _ = __yix_row_1; return ui.view.render(__yix_scope_1, __yix_cx_1, ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure/keyword_for:2", .receiver = "text", .tokens = "text style = @static; box = S . fill_box ; line . text  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . log_line ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . fill_box ", .kind = .property, .literal = null }, } }, .{ .line = line, }, ui.view.text(.{ .style = S.log_line, .box = S.fill_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d1: {
        const __yix_T = @TypeOf(line.peek().text);
        break :__yix_d1 try __yix_scope_1.derive(__yix_T, .{ .line = line, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.line.get().text;
        } }.__yix_compute);
    }), ""), .{ __yix_d1: {
        const __yix_T = @TypeOf(line.peek().text);
        break :__yix_d1 try __yix_scope_1.derive(__yix_T, .{ .line = line, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.line.get().text;
        } }.__yix_compute);
    }, })))); } }.__yix_row); }),
                })),
                ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "row", .tokens = "row style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . actions ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.row(.{ .style = S.actions, }, .{
                    ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "W.Button", .tokens = "< W . Button testId = { ids . edit } label = \"编辑主机\" variant = { . secondary } visible = { vm . p ( ) . can_edit } onClick = { send ( vm , . edit ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "ids . edit ", .kind = .property, .literal = null }, .{ .name = "label", .tokens = "\"编辑主机\" ", .kind = .property, .literal = .{ .text = "编辑主机" } }, .{ .name = "variant", .tokens = ". secondary ", .kind = .property, .literal = .{ .enum_name = "secondary" } }, .{ .name = "visible", .tokens = "vm . p ( ) . can_edit ", .kind = .property, .literal = null }, .{ .name = "on_click", .tokens = "send ( vm , . edit ) ", .kind = .event, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.templateAttrs(.{ .test_id = ids.edit, .visible = __yix_d25: {
        const __yix_T = if (ui.view.attrType(W.Button, "visible")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().p().can_edit);
        break :__yix_d25 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().p().can_edit;
        } }.__yix_compute);
    }, }, __yix_builder_8355: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_8355 W.Button(.{ .label = "编辑主机", .variant = .secondary, .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); send(__yix_ctx.vm.peek(), .edit);  } }.__yix_run) else __yix_d26: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(send(__yix_view_ctx.vm.peek(), .edit));
        break :__yix_d26 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return send(__yix_ctx.vm.get(), .edit);
        } }.__yix_compute);
    }, }); })),
                    ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "W.Button", .tokens = "< W . Button testId = { ids . logs_toggle } label = { vm . p ( ) . logs_label } variant = { . ghost } disabled = { vm . logsDisabled ( ) } onClick = { send ( vm , . toggle_logs ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "ids . logs_toggle ", .kind = .property, .literal = null }, .{ .name = "label", .tokens = "vm . p ( ) . logs_label ", .kind = .property, .literal = null }, .{ .name = "variant", .tokens = ". ghost ", .kind = .property, .literal = .{ .enum_name = "ghost" } }, .{ .name = "disabled", .tokens = "vm . logsDisabled ( ) ", .kind = .property, .literal = null }, .{ .name = "on_click", .tokens = "send ( vm , . toggle_logs ) ", .kind = .event, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.templateAttrs(.{ .test_id = ids.logs_toggle, }, __yix_builder_8500: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_8500 W.Button(.{ .label = __yix_d27: {
        const __yix_T = if (ui.view.attrType(W.Button, "label")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().p().logs_label);
        break :__yix_d27 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().p().logs_label;
        } }.__yix_compute);
    }, .variant = .ghost, .disabled = __yix_d28: {
        const __yix_T = if (ui.view.attrType(W.Button, "disabled")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().logsDisabled());
        break :__yix_d28 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().logsDisabled();
        } }.__yix_compute);
    }, .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); send(__yix_ctx.vm.peek(), .toggle_logs);  } }.__yix_run) else __yix_d29: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(send(__yix_view_ctx.vm.peek(), .toggle_logs));
        break :__yix_d29 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return send(__yix_ctx.vm.get(), .toggle_logs);
        } }.__yix_compute);
    }, }); })),
                    ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "spacer", .tokens = "spacer ", .literal_text = null, .attributes = &.{ } }, .{ }, ui.view.spacer()),
                    ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "W.Button", .tokens = "< W . Button testId = { ids . stop_retry } label = \"停止重试\" variant = { . ghost } visible = { vm . p ( ) . stop_retry } onClick = { send ( vm , . stop_retry ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "ids . stop_retry ", .kind = .property, .literal = null }, .{ .name = "label", .tokens = "\"停止重试\" ", .kind = .property, .literal = .{ .text = "停止重试" } }, .{ .name = "variant", .tokens = ". ghost ", .kind = .property, .literal = .{ .enum_name = "ghost" } }, .{ .name = "visible", .tokens = "vm . p ( ) . stop_retry ", .kind = .property, .literal = null }, .{ .name = "on_click", .tokens = "send ( vm , . stop_retry ) ", .kind = .event, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.templateAttrs(.{ .test_id = ids.stop_retry, .visible = __yix_d30: {
        const __yix_T = if (ui.view.attrType(W.Button, "visible")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().p().stop_retry);
        break :__yix_d30 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().p().stop_retry;
        } }.__yix_compute);
    }, }, __yix_builder_8694: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_8694 W.Button(.{ .label = "停止重试", .variant = .ghost, .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); send(__yix_ctx.vm.peek(), .stop_retry);  } }.__yix_run) else __yix_d31: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(send(__yix_view_ctx.vm.peek(), .stop_retry));
        break :__yix_d31 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return send(__yix_ctx.vm.get(), .stop_retry);
        } }.__yix_compute);
    }, }); })),
                    ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "W.Button", .tokens = "< W . Button testId = { ids . disconnect } label = \"断开\" variant = { . ghost } visible = { vm . p ( ) . disconnect } onClick = { send ( vm , . disconnect ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "ids . disconnect ", .kind = .property, .literal = null }, .{ .name = "label", .tokens = "\"断开\" ", .kind = .property, .literal = .{ .text = "断开" } }, .{ .name = "variant", .tokens = ". ghost ", .kind = .property, .literal = .{ .enum_name = "ghost" } }, .{ .name = "visible", .tokens = "vm . p ( ) . disconnect ", .kind = .property, .literal = null }, .{ .name = "on_click", .tokens = "send ( vm , . disconnect ) ", .kind = .event, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.templateAttrs(.{ .test_id = ids.disconnect, .visible = __yix_d32: {
        const __yix_T = if (ui.view.attrType(W.Button, "visible")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().p().disconnect);
        break :__yix_d32 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().p().disconnect;
        } }.__yix_compute);
    }, }, __yix_builder_8849: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_8849 W.Button(.{ .label = "断开", .variant = .ghost, .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); send(__yix_ctx.vm.peek(), .disconnect);  } }.__yix_run) else __yix_d33: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(send(__yix_view_ctx.vm.peek(), .disconnect));
        break :__yix_d33 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return send(__yix_ctx.vm.get(), .disconnect);
        } }.__yix_compute);
    }, }); })),
                    ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "W.Button", .tokens = "< W . Button testId = { ids . retry_now } label = \"立即重试\" variant = { retryVariant ( vm . p ( ) ) } visible = { vm . p ( ) . retry_now } disabled = { vm . p ( ) . retry_disabled } onClick = { send ( vm , . retry_now ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "ids . retry_now ", .kind = .property, .literal = null }, .{ .name = "label", .tokens = "\"立即重试\" ", .kind = .property, .literal = .{ .text = "立即重试" } }, .{ .name = "variant", .tokens = "retryVariant ( vm . p ( ) ) ", .kind = .property, .literal = null }, .{ .name = "visible", .tokens = "vm . p ( ) . retry_now ", .kind = .property, .literal = null }, .{ .name = "disabled", .tokens = "vm . p ( ) . retry_disabled ", .kind = .property, .literal = null }, .{ .name = "on_click", .tokens = "send ( vm , . retry_now ) ", .kind = .event, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.templateAttrs(.{ .test_id = ids.retry_now, .visible = __yix_d35: {
        const __yix_T = if (ui.view.attrType(W.Button, "visible")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().p().retry_now);
        break :__yix_d35 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().p().retry_now;
        } }.__yix_compute);
    }, }, __yix_builder_8998: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_8998 W.Button(.{ .label = "立即重试", .variant = __yix_d34: {
        const __yix_T = if (ui.view.attrType(W.Button, "variant")) |__yix_A| __yix_A else @TypeOf(retryVariant(__yix_view_ctx.vm.peek().p()));
        break :__yix_d34 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return retryVariant(__yix_ctx.vm.get().p());
        } }.__yix_compute);
    }, .disabled = __yix_d36: {
        const __yix_T = if (ui.view.attrType(W.Button, "disabled")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().p().retry_disabled);
        break :__yix_d36 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().p().retry_disabled;
        } }.__yix_compute);
    }, .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); send(__yix_ctx.vm.peek(), .retry_now);  } }.__yix_run) else __yix_d37: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(send(__yix_view_ctx.vm.peek(), .retry_now));
        break :__yix_d37 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return send(__yix_ctx.vm.get(), .retry_now);
        } }.__yix_compute);
    }, }); })),
                    ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "W.Button", .tokens = "< W . Button testId = { ids . credentials } label = \"重新输入凭据\" variant = { . primary } visible = { vm . p ( ) . credentials } onClick = { send ( vm , . credentials ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "ids . credentials ", .kind = .property, .literal = null }, .{ .name = "label", .tokens = "\"重新输入凭据\" ", .kind = .property, .literal = .{ .text = "重新输入凭据" } }, .{ .name = "variant", .tokens = ". primary ", .kind = .property, .literal = .{ .enum_name = "primary" } }, .{ .name = "visible", .tokens = "vm . p ( ) . credentials ", .kind = .property, .literal = null }, .{ .name = "on_click", .tokens = "send ( vm , . credentials ) ", .kind = .event, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.templateAttrs(.{ .test_id = ids.credentials, .visible = __yix_d38: {
        const __yix_T = if (ui.view.attrType(W.Button, "visible")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().p().credentials);
        break :__yix_d38 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().p().credentials;
        } }.__yix_compute);
    }, }, __yix_builder_9197: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_9197 W.Button(.{ .label = "重新输入凭据", .variant = .primary, .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); send(__yix_ctx.vm.peek(), .credentials);  } }.__yix_run) else __yix_d39: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(send(__yix_view_ctx.vm.peek(), .credentials));
        break :__yix_d39 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return send(__yix_ctx.vm.get(), .credentials);
        } }.__yix_compute);
    }, }); })),
                    ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "W.Button", .tokens = "< W . Button testId = { ids . trust_key } label = { replace_key } variant = { . danger } visible = { vm . p ( ) . trust_key } onClick = { send ( vm , . trust_key ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "ids . trust_key ", .kind = .property, .literal = null }, .{ .name = "label", .tokens = "replace_key ", .kind = .property, .literal = null }, .{ .name = "variant", .tokens = ". danger ", .kind = .property, .literal = .{ .enum_name = "danger" } }, .{ .name = "visible", .tokens = "vm . p ( ) . trust_key ", .kind = .property, .literal = null }, .{ .name = "on_click", .tokens = "send ( vm , . trust_key ) ", .kind = .event, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.templateAttrs(.{ .test_id = ids.trust_key, .visible = __yix_d40: {
        const __yix_T = if (ui.view.attrType(W.Button, "visible")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().p().trust_key);
        break :__yix_d40 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().p().trust_key;
        } }.__yix_compute);
    }, }, __yix_builder_9363: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_9363 W.Button(.{ .label = replace_key, .variant = .danger, .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); send(__yix_ctx.vm.peek(), .trust_key);  } }.__yix_run) else __yix_d41: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(send(__yix_view_ctx.vm.peek(), .trust_key));
        break :__yix_d41 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return send(__yix_ctx.vm.get(), .trust_key);
        } }.__yix_compute);
    }, }); })),
                })),
            })),
            ui.view.templateSite(.{ .module = "src/features/connections/progress/view/connection_failure.yix", .path = "ConnectionFailure", .receiver = "W.ConfirmDialog", .tokens = "< W . ConfirmDialog testId = { ids . trust_confirm } open = { trustOpen ( vm ) } title = \"替换主机密钥？\" message = \"服务器当前提供的密钥与已保存的不同。替换会覆盖已保存的密钥并用新密钥继续连接；请先核对新指纹，确认服务器确实更换过密钥。\" confirmLabel = { replace_key } cancelLabel = { Confirm . cancel_label } closeOnOverlay = { Confirm . close_on_overlay } onConfirm = { trustConfirmed ( vm ) } onCancel = { trustCancelled ( vm ) } testIds = { . { . cancel = ids . trust_confirm_cancel , . confirm = ids . trust_confirm_accept } } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "ids . trust_confirm ", .kind = .property, .literal = null }, .{ .name = "open", .tokens = "trustOpen ( vm ) ", .kind = .property, .literal = null }, .{ .name = "title", .tokens = "\"替换主机密钥？\" ", .kind = .property, .literal = .{ .text = "替换主机密钥？" } }, .{ .name = "message", .tokens = "\"服务器当前提供的密钥与已保存的不同。替换会覆盖已保存的密钥并用新密钥继续连接；请先核对新指纹，确认服务器确实更换过密钥。\" ", .kind = .property, .literal = .{ .text = "服务器当前提供的密钥与已保存的不同。替换会覆盖已保存的密钥并用新密钥继续连接；请先核对新指纹，确认服务器确实更换过密钥。" } }, .{ .name = "confirm_label", .tokens = "replace_key ", .kind = .property, .literal = null }, .{ .name = "cancel_label", .tokens = "Confirm . cancel_label ", .kind = .property, .literal = null }, .{ .name = "close_on_overlay", .tokens = "Confirm . close_on_overlay ", .kind = .property, .literal = null }, .{ .name = "on_confirm", .tokens = "trustConfirmed ( vm ) ", .kind = .event, .literal = null }, .{ .name = "on_cancel", .tokens = "trustCancelled ( vm ) ", .kind = .event, .literal = null }, .{ .name = "test_ids", .tokens = ". { . cancel = ids . trust_confirm_cancel , . confirm = ids . trust_confirm_accept } ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.templateAttrs(.{ .test_id = ids.trust_confirm, }, __yix_builder_9549: { try ui.view.previewCheckBuilder(__yix_view_scope, W.ConfirmDialog); break :__yix_builder_9549 W.ConfirmDialog(.{ .open = __yix_d42: {
        const __yix_T = if (ui.view.attrType(W.ConfirmDialog, "open")) |__yix_A| __yix_A else @TypeOf(trustOpen(__yix_view_ctx.vm.peek()));
        break :__yix_d42 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return trustOpen(__yix_ctx.vm.get());
        } }.__yix_compute);
    }, .title = "替换主机密钥？", .message = "服务器当前提供的密钥与已保存的不同。替换会覆盖已保存的密钥并用新密钥继续连接；请先核对新指纹，确认服务器确实更换过密钥。", .confirm_label = replace_key, .cancel_label = Confirm.cancel_label, .close_on_overlay = Confirm.close_on_overlay, .on_confirm = if (comptime ui.view.isEventProp(W.ConfirmDialog, "on_confirm")) try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); trustConfirmed(__yix_ctx.vm.peek());  } }.__yix_run) else __yix_d43: {
        const __yix_T = if (ui.view.attrType(W.ConfirmDialog, "on_confirm")) |__yix_A| __yix_A else @TypeOf(trustConfirmed(__yix_view_ctx.vm.peek()));
        break :__yix_d43 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return trustConfirmed(__yix_ctx.vm.get());
        } }.__yix_compute);
    }, .on_cancel = if (comptime ui.view.isEventProp(W.ConfirmDialog, "on_cancel")) try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); trustCancelled(__yix_ctx.vm.peek());  } }.__yix_run) else __yix_d44: {
        const __yix_T = if (ui.view.attrType(W.ConfirmDialog, "on_cancel")) |__yix_A| __yix_A else @TypeOf(trustCancelled(__yix_view_ctx.vm.peek()));
        break :__yix_d44 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return trustCancelled(__yix_ctx.vm.get());
        } }.__yix_compute);
    }, .test_ids = .{ .cancel = ids.trust_confirm_cancel, .confirm = ids.trust_confirm_accept }, }); })),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "ConnectionFailure";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

const __yix_preview_source: ?[]const u8 = if (ui.view.template.preview_enabled) "\x2f\x2f\x21\x20\xe8\xbf\x9e\xe6\x8e\xa5\xe5\xa4\xb1\xe8\xb4\xa5\x20\x2f\x20\xe9\x87\x8d\xe8\xaf\x95\xe8\xa7\x86\xe5\x9b\xbe\xef\xbc\x88\x64\x65\x73\x69\x67\x6e\x2d\x72\x33\x20\xe7\xa8\xbf\x20\x31\xef\xbc\x8c\x50\x65\x6e\x63\x69\x6c\x20\x52\x44\x69\x6f\x62\x20\xe2\x80\xba\x20\x48\x77\x73\x77\x6c\xef\xbc\x89\xef\xbc\x9a\xe4\xbc\x9a\xe8\xaf\x9d\x20\x74\x61\x62\x20\xe5\x86\x85\xe5\xae\xb9\xe5\x8c\xba\xe9\x87\x8c\xe5\xb1\x85\xe4\xb8\xad\xe7\x9a\x84\xe4\xb8\x80\xe5\x88\x97\xef\xbc\x88\xe5\xae\xbd\x20\x35\x36\x30\xef\xbc\x89\xef\xbc\x8c\x0a\x2f\x2f\x21\x20\xe6\x9b\xbf\xe4\xbb\xa3\xe8\xbf\x9e\xe6\x8e\xa5\xe8\xbf\x9b\xe5\xba\xa6\xe5\x8d\xa1\xe7\x89\x87\xe7\x9a\x84\xe5\xa4\xb1\xe8\xb4\xa5\xe6\x80\x81\xe4\xb8\x8e\xe7\xad\x89\xe5\xbe\x85\xe8\x87\xaa\xe5\x8a\xa8\xe9\x87\x8d\xe8\xaf\x95\xe6\x80\x81\xe3\x80\x82\xe5\x8f\xaa\xe7\x94\xa8\x20\x7a\x65\x6e\x69\x74\x20\xe5\x8e\x9f\xe7\x94\x9f\xe7\xbb\x84\xe4\xbb\xb6\xef\xbc\x8c\xe5\xa4\x96\xe8\xa7\x82\xe5\x85\xa8\xe6\x98\xaf\xe9\xbb\x98\xe8\xae\xa4\xef\xbc\x9a\x0a\x2f\x2f\x21\x0a\x2f\x2f\x21\x20\x2d\x20\xe5\xa4\xb4\xe9\x83\xa8\xef\xbc\x9a\xe5\xa4\xb1\xe8\xb4\xa5\xe7\xb1\xbb\xe5\x88\xab\xe5\x9b\xbe\xe6\xa0\x87\xe3\x80\x81\xe4\xb8\xbb\xe6\x9c\xba\xe5\x90\x8d\xe3\x80\x81\x60\x75\x73\x65\x72\x40\x68\x6f\x73\x74\x3a\x70\x6f\x72\x74\x60\xef\xbc\x88\xe7\xad\x89\xe5\xae\xbd\xef\xbc\x89\xe3\x80\x81\xe5\x8f\xb3\xe4\xbe\xa7\xe5\x8e\x9f\xe7\x94\x9f\x20\x60\x57\x2e\x53\x74\x61\x74\x75\x73\x42\x61\x64\x67\x65\x60\xef\xbc\x88\xe2\x80\x9c\x4e\x20\xe7\xa7\x92\xe5\x90\x8e\xe9\x87\x8d\xe8\xaf\x95\x20\x2f\x20\xe5\xb7\xb2\xe5\x81\x9c\xe6\xad\xa2\xe9\x87\x8d\xe8\xaf\x95\x20\x2f\x20\xe9\x9c\x80\xe8\xa6\x81\xe7\xa1\xae\xe8\xae\xa4\xe2\x80\x9d\xef\xbc\x89\xe3\x80\x82\x0a\x2f\x2f\x21\x20\x2d\x20\xe4\xb8\x80\xe5\x8f\xa5\xe8\xaf\x9d\xe6\xa0\x87\xe9\xa2\x98\xef\xbc\x9b\xe5\xa4\xb1\xe8\xb4\xa5\xe5\x8e\x9f\xe5\x9b\xa0\xe6\x98\xaf\xe5\x8e\x9f\xe7\x94\x9f\x20\x60\x57\x2e\x41\x6c\x65\x72\x74\x60\xef\xbc\x88\x65\x72\x72\x6f\x72\x20\x2f\x20\x77\x61\x72\x6e\x69\x6e\x67\xef\xbc\x89\xef\xbc\x8c\xe5\x86\x99\xe6\x98\x8e\xe5\x85\xb7\xe4\xbd\x93\xe5\x9c\xb0\xe5\x9d\x80\xe3\x80\x81\xe7\xab\xaf\xe5\x8f\xa3\xe3\x80\x81\xe7\x94\xa8\xe6\x88\xb7\xe5\x90\x8d\xe3\x80\x82\x0a\x2f\x2f\x21\x20\x2d\x20\xe5\x8f\xaa\xe6\x9c\x89\xe7\xa1\xae\xe5\xae\x9e\xe5\x9c\xa8\xe7\xad\x89\xe4\xb8\x80\xe6\xac\xa1\xe8\x87\xaa\xe5\x8a\xa8\xe9\x87\x8d\xe8\xaf\x95\xe6\x97\xb6\xe6\x89\x8d\xe6\x9c\x89\xe9\x87\x8d\xe8\xaf\x95\xe8\xa1\x8c\xef\xbc\x9a\xe8\xaf\xb4\xe6\x98\x8e\xe6\x96\x87\xe5\xad\x97\x20\x2b\x20\xe5\x8e\x9f\xe7\x94\x9f\x20\x60\x57\x2e\x50\x72\x6f\x67\x72\x65\x73\x73\x60\x20\xe5\x80\x92\xe8\xae\xa1\xe6\x97\xb6\xe6\x9d\xa1\xef\xbc\x9b\xe4\xb8\x8d\xe9\x87\x8d\xe8\xaf\x95\xe6\x97\xb6\xe4\xb8\x80\xe8\xa1\x8c\xe8\xaf\xb4\xe6\x98\x8e\xe4\xb8\xba\xe4\xbb\x80\xe4\xb9\x88\xe3\x80\x82\x0a\x2f\x2f\x21\x20\x2d\x20\xe4\xb8\xbb\xe6\x9c\xba\xe5\xaf\x86\xe9\x92\xa5\xe5\x8f\x98\xe6\x9b\xb4\xef\xbc\x9a\xe2\x80\x9c\xe5\xb7\xb2\xe4\xbf\x9d\xe5\xad\x98\xe7\x9a\x84\xe5\xaf\x86\xe9\x92\xa5\xe2\x80\x9d\xe4\xb8\x8e\xe2\x80\x9c\xe6\x9c\x8d\xe5\x8a\xa1\xe5\x99\xa8\xe5\xbd\x93\xe5\x89\x8d\xe6\x8f\x90\xe4\xbe\x9b\xe7\x9a\x84\xe5\xaf\x86\xe9\x92\xa5\xe2\x80\x9d\xe4\xb8\xa4\xe5\x9d\x97\xe6\x8c\x87\xe7\xba\xb9\xef\xbc\x88\xe5\x90\x8e\xe8\x80\x85\xe7\x94\xa8\xe5\x8d\xb1\xe9\x99\xa9\xe8\x89\xb2\xef\xbc\x89\xe3\x80\x82\x0a\x2f\x2f\x21\x20\x2d\x20\xe9\x80\x90\xe8\xb7\xb3\xe8\xbf\x9e\xe6\x8e\xa5\xe8\xb7\xaf\xe5\xbe\x84\xef\xbc\x9a\xe6\x9c\xac\xe6\x9c\xba\x20\xe2\x86\x92\x20\xe5\x90\x84\xe8\xb7\xb3\x20\xe2\x86\x92\x20\xe7\x9b\xae\xe6\xa0\x87\xef\xbc\x8c\xe7\x8a\xb6\xe6\x80\x81\xe7\x94\xa8\xe7\x94\xa8\xe6\x88\xb7\xe8\x83\xbd\xe7\x9c\x8b\xe6\x87\x82\xe7\x9a\x84\xe8\xaf\xb4\xe6\xb3\x95\xe3\x80\x82\x0a\x2f\x2f\x21\x20\x2d\x20\xe6\x93\x8d\xe4\xbd\x9c\xe8\xa1\x8c\xef\xbc\x9a\xe5\xb7\xa6\xe2\x80\x9c\xe7\xbc\x96\xe8\xbe\x91\xe8\xbf\x9e\xe6\x8e\xa5\xe2\x80\x9d\xef\xbc\x88\x73\x65\x63\x6f\x6e\x64\x61\x72\x79\xef\xbc\x89\xe2\x80\x9c\xe6\x9f\xa5\xe7\x9c\x8b\xe6\x97\xa5\xe5\xbf\x97\x20\x2f\x20\xe6\x94\xb6\xe8\xb5\xb7\xe6\x97\xa5\xe5\xbf\x97\xe2\x80\x9d\xef\xbc\x88\x67\x68\x6f\x73\x74\xef\xbc\x89\xef\xbc\x9b\xe5\x8f\xb3\xe7\xbb\xa7\xe7\xbb\xad\xe7\xb1\xbb\xe6\x93\x8d\xe4\xbd\x9c\xef\xbc\x8c\xe4\xb8\xbb\xe6\x8c\x89\xe9\x92\xae\xe5\x9c\xa8\xe6\x9c\x80\xe5\x8f\xb3\x0a\x2f\x2f\x21\x20\x20\x20\xef\xbc\x88\xe7\xab\x8b\xe5\x8d\xb3\xe9\x87\x8d\xe8\xaf\x95\x20\x2f\x20\xe9\x87\x8d\xe6\x96\xb0\xe8\xbe\x93\xe5\x85\xa5\xe5\x87\xad\xe6\x8d\xae\x20\x2f\x20\xe2\x80\x9c\xe6\x9b\xbf\xe6\x8d\xa2\xe4\xb8\xbb\xe6\x9c\xba\xe5\xaf\x86\xe9\x92\xa5\xe2\x80\x9d\xe7\x94\xa8\x20\x64\x61\x6e\x67\x65\x72\xef\xbc\x9b\xe6\x9b\xbf\xe6\x8d\xa2\xe5\x89\x8d\xe5\x85\x88\xe5\xbc\xb9\xe5\x8e\x9f\xe7\x94\x9f\xe7\xa1\xae\xe8\xae\xa4\xe6\xa1\x86\x20\x60\x57\x2e\x43\x6f\x6e\x66\x69\x72\x6d\x44\x69\x61\x6c\x6f\x67\x60\xef\xbc\x8c\xe8\xa7\x84\xe5\x88\x99\xe5\x8f\x96\x0a\x2f\x2f\x21\x20\x20\x20\x60\x73\x68\x61\x72\x65\x64\x2f\x75\x69\x2f\x63\x6f\x6e\x66\x69\x72\x6d\x60\xef\xbc\x9a\xe7\x84\xa6\xe7\x82\xb9\xe5\x9c\xa8\xe2\x80\x9c\xe5\x8f\x96\xe6\xb6\x88\xe2\x80\x9d\xef\xbc\x8c\x45\x73\x63\x20\x2f\x20\xc3\x97\x20\x2f\x20\xe7\x82\xb9\xe9\x81\xae\xe7\xbd\xa9\x20\x3d\x20\xe5\x8f\x96\xe6\xb6\x88\xef\xbc\x89\xe3\x80\x82\x0a\x2f\x2f\x21\x20\xe6\x96\x87\xe6\xa1\x88\xe4\xb8\x8e\xe7\x8a\xb6\xe6\x80\x81\xe5\x85\xa8\xe9\x83\xa8\xe6\x9d\xa5\xe8\x87\xaa\x20\x60\x6d\x6f\x64\x65\x6c\x2f\x66\x61\x69\x6c\x75\x72\x65\x5f\x76\x69\x65\x77\x2e\x7a\x69\x67\x60\x20\xe7\x9a\x84\xe6\x8a\x95\xe5\xbd\xb1\xef\xbc\x9b\xe8\xbf\x99\xe9\x87\x8c\xe4\xb8\x8d\xe5\x81\x9a\xe5\x88\xa4\xe6\x96\xad\xef\xbc\x8c\xe5\x8f\xaa\xe6\x8a\x8a\xe7\x82\xb9\xe5\x87\xbb\xe4\xba\xa4\xe7\xbb\x99\x20\x60\x46\x61\x69\x6c\x75\x72\x65\x56\x69\x65\x77\x2e\x61\x63\x74\x60\xe3\x80\x82\x0a\x63\x6f\x6e\x73\x74\x20\x75\x69\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x75\x69\x22\x29\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x57\x20\x3d\x20\x75\x69\x2e\x77\x69\x64\x67\x65\x74\x73\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x6d\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x2e\x2e\x2f\x6d\x6f\x64\x65\x6c\x2f\x66\x61\x69\x6c\x75\x72\x65\x5f\x76\x69\x65\x77\x2e\x7a\x69\x67\x22\x29\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x43\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x66\x61\x69\x6c\x75\x72\x65\x5f\x63\x6f\x6e\x74\x72\x6f\x6c\x6c\x65\x72\x2e\x7a\x69\x67\x22\x29\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x53\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x63\x6f\x6e\x6e\x65\x63\x74\x69\x6f\x6e\x5f\x66\x61\x69\x6c\x75\x72\x65\x2e\x79\x73\x73\x22\x29\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x43\x6f\x6e\x66\x69\x72\x6d\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x2e\x2e\x2f\x2e\x2e\x2f\x2e\x2e\x2f\x2e\x2e\x2f\x73\x68\x61\x72\x65\x64\x2f\x75\x69\x2f\x63\x6f\x6e\x66\x69\x72\x6d\x2f\x63\x6f\x6e\x66\x69\x72\x6d\x2e\x7a\x69\x67\x22\x29\x3b\x0a\x0a\x70\x75\x62\x20\x63\x6f\x6e\x73\x74\x20\x69\x64\x73\x20\x3d\x20\x73\x74\x72\x75\x63\x74\x20\x7b\x0a\x20\x20\x20\x20\x70\x75\x62\x20\x63\x6f\x6e\x73\x74\x20\x72\x6f\x6f\x74\x20\x3d\x20\x22\x63\x6f\x6e\x6e\x65\x63\x74\x69\x6f\x6e\x2e\x70\x72\x6f\x67\x72\x65\x73\x73\x2e\x66\x61\x69\x6c\x75\x72\x65\x22\x3b\x0a\x20\x20\x20\x20\x70\x75\x62\x20\x63\x6f\x6e\x73\x74\x20\x62\x61\x64\x67\x65\x20\x3d\x20\x22\x63\x6f\x6e\x6e\x65\x63\x74\x69\x6f\x6e\x2e\x70\x72\x6f\x67\x72\x65\x73\x73\x2e\x66\x61\x69\x6c\x75\x72\x65\x2e\x62\x61\x64\x67\x65\x22\x3b\x0a\x20\x20\x20\x20\x70\x75\x62\x20\x63\x6f\x6e\x73\x74\x20\x74\x69\x74\x6c\x65\x20\x3d\x20\x22\x63\x6f\x6e\x6e\x65\x63\x74\x69\x6f\x6e\x2e\x70\x72\x6f\x67\x72\x65\x73\x73\x2e\x66\x61\x69\x6c\x75\x72\x65\x2e\x74\x69\x74\x6c\x65\x22\x3b\x0a\x20\x20\x20\x20\x70\x75\x62\x20\x63\x6f\x6e\x73\x74\x20\x61\x6c\x65\x72\x74\x20\x3d\x20\x22\x63\x6f\x6e\x6e\x65\x63\x74\x69\x6f\x6e\x2e\x70\x72\x6f\x67\x72\x65\x73\x73\x2e\x66\x61\x69\x6c\x75\x72\x65\x2e\x61\x6c\x65\x72\x74\x22\x3b\x0a\x20\x20\x20\x20\x70\x75\x62\x20\x63\x6f\x6e\x73\x74\x20\x72\x65\x74\x72\x79\x20\x3d\x20\x22\x63\x6f\x6e\x6e\x65\x63\x74\x69\x6f\x6e\x2e\x70\x72\x6f\x67\x72\x65\x73\x73\x2e\x66\x61\x69\x6c\x75\x72\x65\x2e\x72\x65\x74\x72\x79\x22\x3b\x0a\x20\x20\x20\x20\x70\x75\x62\x20\x63\x6f\x6e\x73\x74\x20\x72\x65\x74\x72\x79\x5f\x62\x61\x72\x20\x3d\x20\x22\x63\x6f\x6e\x6e\x65\x63\x74\x69\x6f\x6e\x2e\x70\x72\x6f\x67\x72\x65\x73\x73\x2e\x66\x61\x69\x6c\x75\x72\x65\x2e\x72\x65\x74\x72\x79\x2e\x62\x61\x72\x22\x3b\x0a\x20\x20\x20\x20\x70\x75\x62\x20\x63\x6f\x6e\x73\x74\x20\x68\x6f\x6c\x64\x20\x3d\x20\x22\x63\x6f\x6e\x6e\x65\x63\x74\x69\x6f\x6e\x2e\x70\x72\x6f\x67\x72\x65\x73\x73\x2e\x66\x61\x69\x6c\x75\x72\x65\x2e\x68\x6f\x6c\x64\x22\x3b\x0a\x20\x20\x20\x20\x70\x75\x62\x20\x63\x6f\x6e\x73\x74\x20\x73\x61\x76\x65\x64\x5f\x6b\x65\x79\x20\x3d\x20\x22\x63\x6f\x6e\x6e\x65\x63\x74\x69\x6f\x6e\x2e\x70\x72\x6f\x67\x72\x65\x73\x73\x2e\x66\x61\x69\x6c\x75\x72\x65\x2e\x6b\x65\x79\x2e\x73\x61\x76\x65\x64\x22\x3b\x0a\x20\x20\x20\x20\x70\x75\x62\x20\x63\x6f\x6e\x73\x74\x20\x6f\x66\x66\x65\x72\x65\x64\x5f\x6b\x65\x79\x20\x3d\x20\x22\x63\x6f\x6e\x6e\x65\x63\x74\x69\x6f\x6e\x2e\x70\x72\x6f\x67\x72\x65\x73\x73\x2e\x66\x61\x69\x6c\x75\x72\x65\x2e\x6b\x65\x79\x2e\x6f\x66\x66\x65\x72\x65\x64\x22\x3b\x0a\x20\x20\x20\x20\x70\x75\x62\x20\x63\x6f\x6e\x73\x74\x20\x72\x6f\x75\x74\x65\x20\x3d\x20\x22\x63\x6f\x6e\x6e\x65\x63\x74\x69\x6f\x6e\x2e\x70\x72\x6f\x67\x72\x65\x73\x73\x2e\x66\x61\x69\x6c\x75\x72\x65\x2e\x72\x6f\x75\x74\x65\x22\x3b\x0a\x20\x20\x20\x20\x70\x75\x62\x20\x63\x6f\x6e\x73\x74\x20\x68\x6f\x70\x20\x3d\x20\x22\x63\x6f\x6e\x6e\x65\x63\x74\x69\x6f\x6e\x2e\x70\x72\x6f\x67\x72\x65\x73\x73\x2e\x66\x61\x69\x6c\x75\x72\x65\x2e\x68\x6f\x70\x22\x3b\x0a\x20\x20\x20\x20\x70\x75\x62\x20\x63\x6f\x6e\x73\x74\x20\x6c\x6f\x67\x73\x20\x3d\x20\x22\x63\x6f\x6e\x6e\x65\x63\x74\x69\x6f\x6e\x2e\x70\x72\x6f\x67\x72\x65\x73\x73\x2e\x66\x61\x69\x6c\x75\x72\x65\x2e\x6c\x6f\x67\x73\x22\x3b\x0a\x20\x20\x20\x20\x70\x75\x62\x20\x63\x6f\x6e\x73\x74\x20\x65\x64\x69\x74\x20\x3d\x20\x22\x63\x6f\x6e\x6e\x65\x63\x74\x69\x6f\x6e\x2e\x70\x72\x6f\x67\x72\x65\x73\x73\x2e\x66\x61\x69\x6c\x75\x72\x65\x2e\x65\x64\x69\x74\x22\x3b\x0a\x20\x20\x20\x20\x70\x75\x62\x20\x63\x6f\x6e\x73\x74\x20\x6c\x6f\x67\x73\x5f\x74\x6f\x67\x67\x6c\x65\x20\x3d\x20\x22\x63\x6f\x6e\x6e\x65\x63\x74\x69\x6f\x6e\x2e\x70\x72\x6f\x67\x72\x65\x73\x73\x2e\x66\x61\x69\x6c\x75\x72\x65\x2e\x6c\x6f\x67\x73\x2e\x74\x6f\x67\x67\x6c\x65\x22\x3b\x0a\x20\x20\x20\x20\x70\x75\x62\x20\x63\x6f\x6e\x73\x74\x20\x73\x74\x6f\x70\x5f\x72\x65\x74\x72\x79\x20\x3d\x20\x22\x63\x6f\x6e\x6e\x65\x63\x74\x69\x6f\x6e\x2e\x70\x72\x6f\x67\x72\x65\x73\x73\x2e\x66\x61\x69\x6c\x75\x72\x65\x2e\x73\x74\x6f\x70\x22\x3b\x0a\x20\x20\x20\x20\x70\x75\x62\x20\x63\x6f\x6e\x73\x74\x20\x72\x65\x74\x72\x79\x5f\x6e\x6f\x77\x20\x3d\x20\x22\x63\x6f\x6e\x6e\x65\x63\x74\x69\x6f\x6e\x2e\x70\x72\x6f\x67\x72\x65\x73\x73\x2e\x66\x61\x69\x6c\x75\x72\x65\x2e\x72\x65\x74\x72\x79\x5f\x6e\x6f\x77\x22\x3b\x0a\x20\x20\x20\x20\x70\x75\x62\x20\x63\x6f\x6e\x73\x74\x20\x63\x72\x65\x64\x65\x6e\x74\x69\x61\x6c\x73\x20\x3d\x20\x22\x63\x6f\x6e\x6e\x65\x63\x74\x69\x6f\x6e\x2e\x70\x72\x6f\x67\x72\x65\x73\x73\x2e\x66\x61\x69\x6c\x75\x72\x65\x2e\x63\x72\x65\x64\x65\x6e\x74\x69\x61\x6c\x73\x22\x3b\x0a\x20\x20\x20\x20\x70\x75\x62\x20\x63\x6f\x6e\x73\x74\x20\x64\x69\x73\x63\x6f\x6e\x6e\x65\x63\x74\x20\x3d\x20\x22\x63\x6f\x6e\x6e\x65\x63\x74\x69\x6f\x6e\x2e\x70\x72\x6f\x67\x72\x65\x73\x73\x2e\x66\x61\x69\x6c\x75\x72\x65\x2e\x64\x69\x73\x63\x6f\x6e\x6e\x65\x63\x74\x22\x3b\x0a\x20\x20\x20\x20\x70\x75\x62\x20\x63\x6f\x6e\x73\x74\x20\x74\x72\x75\x73\x74\x5f\x6b\x65\x79\x20\x3d\x20\x22\x63\x6f\x6e\x6e\x65\x63\x74\x69\x6f\x6e\x2e\x70\x72\x6f\x67\x72\x65\x73\x73\x2e\x66\x61\x69\x6c\x75\x72\x65\x2e\x74\x72\x75\x73\x74\x22\x3b\x0a\x20\x20\x20\x20\x70\x75\x62\x20\x63\x6f\x6e\x73\x74\x20\x74\x72\x75\x73\x74\x5f\x63\x6f\x6e\x66\x69\x72\x6d\x20\x3d\x20\x22\x63\x6f\x6e\x6e\x65\x63\x74\x69\x6f\x6e\x2e\x70\x72\x6f\x67\x72\x65\x73\x73\x2e\x66\x61\x69\x6c\x75\x72\x65\x2e\x74\x72\x75\x73\x74\x2e\x63\x6f\x6e\x66\x69\x72\x6d\x22\x3b\x0a\x20\x20\x20\x20\x70\x75\x62\x20\x63\x6f\x6e\x73\x74\x20\x74\x72\x75\x73\x74\x5f\x63\x6f\x6e\x66\x69\x72\x6d\x5f\x63\x61\x6e\x63\x65\x6c\x20\x3d\x20\x22\x63\x6f\x6e\x6e\x65\x63\x74\x69\x6f\x6e\x2e\x70\x72\x6f\x67\x72\x65\x73\x73\x2e\x66\x61\x69\x6c\x75\x72\x65\x2e\x74\x72\x75\x73\x74\x2e\x63\x61\x6e\x63\x65\x6c\x22\x3b\x0a\x20\x20\x20\x20\x70\x75\x62\x20\x63\x6f\x6e\x73\x74\x20\x74\x72\x75\x73\x74\x5f\x63\x6f\x6e\x66\x69\x72\x6d\x5f\x61\x63\x63\x65\x70\x74\x20\x3d\x20\x22\x63\x6f\x6e\x6e\x65\x63\x74\x69\x6f\x6e\x2e\x70\x72\x6f\x67\x72\x65\x73\x73\x2e\x66\x61\x69\x6c\x75\x72\x65\x2e\x74\x72\x75\x73\x74\x2e\x61\x63\x63\x65\x70\x74\x22\x3b\x0a\x7d\x3b\x0a\x0a\x63\x6f\x6e\x73\x74\x20\x72\x65\x70\x6c\x61\x63\x65\x5f\x6b\x65\x79\x20\x3d\x20\x43\x6f\x6e\x66\x69\x72\x6d\x2e\x6c\x61\x62\x65\x6c\x28\x2e\x72\x65\x70\x6c\x61\x63\x65\x2c\x20\x22\xe4\xb8\xbb\xe6\x9c\xba\xe5\xaf\x86\xe9\x92\xa5\x22\x29\x3b\x0a\x66\x6e\x20\x74\x72\x75\x73\x74\x4f\x70\x65\x6e\x28\x76\x6d\x3a\x20\x2a\x43\x2e\x46\x61\x69\x6c\x75\x72\x65\x56\x69\x65\x77\x29\x20\x62\x6f\x6f\x6c\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x74\x72\x75\x73\x74\x5f\x63\x6f\x6e\x66\x69\x72\x6d\x2e\x67\x65\x74\x28\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x74\x72\x75\x73\x74\x43\x6f\x6e\x66\x69\x72\x6d\x65\x64\x28\x76\x6d\x3a\x20\x2a\x43\x2e\x46\x61\x69\x6c\x75\x72\x65\x56\x69\x65\x77\x29\x20\x76\x6f\x69\x64\x20\x7b\x0a\x20\x20\x20\x20\x76\x6d\x2e\x74\x72\x75\x73\x74\x43\x6f\x6e\x66\x69\x72\x6d\x65\x64\x28\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x74\x72\x75\x73\x74\x43\x61\x6e\x63\x65\x6c\x6c\x65\x64\x28\x76\x6d\x3a\x20\x2a\x43\x2e\x46\x61\x69\x6c\x75\x72\x65\x56\x69\x65\x77\x29\x20\x76\x6f\x69\x64\x20\x7b\x0a\x20\x20\x20\x20\x76\x6d\x2e\x74\x72\x75\x73\x74\x5f\x63\x6f\x6e\x66\x69\x72\x6d\x2e\x73\x65\x74\x28\x66\x61\x6c\x73\x65\x29\x3b\x0a\x7d\x0a\x0a\x66\x6e\x20\x73\x65\x6e\x64\x28\x76\x6d\x3a\x20\x2a\x43\x2e\x46\x61\x69\x6c\x75\x72\x65\x56\x69\x65\x77\x2c\x20\x61\x63\x74\x69\x6f\x6e\x3a\x20\x43\x2e\x41\x63\x74\x69\x6f\x6e\x29\x20\x76\x6f\x69\x64\x20\x7b\x0a\x20\x20\x20\x20\x76\x6d\x2e\x61\x63\x74\x28\x61\x63\x74\x69\x6f\x6e\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x68\x65\x61\x64\x49\x63\x6f\x6e\x28\x69\x63\x6f\x6e\x3a\x20\x6d\x2e\x49\x63\x6f\x6e\x29\x20\x75\x69\x2e\x53\x76\x67\x41\x73\x73\x65\x74\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x73\x77\x69\x74\x63\x68\x20\x28\x69\x63\x6f\x6e\x29\x20\x7b\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x2e\x72\x65\x66\x75\x73\x65\x64\x2c\x20\x2e\x66\x61\x69\x6c\x65\x64\x20\x3d\x3e\x20\x75\x69\x2e\x69\x63\x6f\x6e\x73\x2e\x63\x69\x72\x63\x6c\x65\x5f\x78\x2c\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x2e\x74\x69\x6d\x65\x6f\x75\x74\x20\x3d\x3e\x20\x75\x69\x2e\x69\x63\x6f\x6e\x73\x2e\x63\x6c\x6f\x63\x6b\x5f\x61\x6c\x65\x72\x74\x2c\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x2e\x73\x68\x69\x65\x6c\x64\x20\x3d\x3e\x20\x75\x69\x2e\x69\x63\x6f\x6e\x73\x2e\x73\x68\x69\x65\x6c\x64\x5f\x61\x6c\x65\x72\x74\x2c\x0a\x20\x20\x20\x20\x7d\x3b\x0a\x7d\x0a\x66\x6e\x20\x68\x65\x61\x64\x54\x6f\x6e\x65\x28\x69\x63\x6f\x6e\x3a\x20\x6d\x2e\x49\x63\x6f\x6e\x29\x20\x53\x2e\x54\x6f\x6e\x65\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x69\x66\x20\x28\x69\x63\x6f\x6e\x20\x3d\x3d\x20\x2e\x74\x69\x6d\x65\x6f\x75\x74\x29\x20\x2e\x77\x61\x72\x6e\x69\x6e\x67\x20\x65\x6c\x73\x65\x20\x2e\x64\x61\x6e\x67\x65\x72\x3b\x0a\x7d\x0a\x2f\x2f\x2f\x20\x54\x68\x65\x20\x66\x6f\x75\x72\x20\x74\x6f\x6e\x65\x20\x72\x65\x63\x69\x70\x65\x73\x20\x73\x68\x61\x72\x65\x20\x76\x61\x72\x69\x61\x6e\x74\x20\x6e\x61\x6d\x65\x73\x3b\x20\x65\x61\x63\x68\x20\x68\x61\x73\x20\x69\x74\x73\x20\x6f\x77\x6e\x20\x64\x69\x6d\x65\x6e\x73\x69\x6f\x6e\x20\x74\x79\x70\x65\x2e\x0a\x66\x6e\x20\x74\x6f\x6e\x65\x4f\x66\x28\x63\x6f\x6d\x70\x74\x69\x6d\x65\x20\x54\x3a\x20\x74\x79\x70\x65\x2c\x20\x74\x6f\x6e\x65\x3a\x20\x6d\x2e\x54\x6f\x6e\x65\x29\x20\x54\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x73\x77\x69\x74\x63\x68\x20\x28\x74\x6f\x6e\x65\x29\x20\x7b\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x2e\x6f\x6b\x20\x3d\x3e\x20\x2e\x6f\x6b\x2c\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x2e\x64\x61\x6e\x67\x65\x72\x20\x3d\x3e\x20\x2e\x64\x61\x6e\x67\x65\x72\x2c\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x2e\x77\x61\x72\x6e\x69\x6e\x67\x20\x3d\x3e\x20\x2e\x77\x61\x72\x6e\x69\x6e\x67\x2c\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x2e\x6d\x75\x74\x65\x64\x20\x3d\x3e\x20\x2e\x6d\x75\x74\x65\x64\x2c\x0a\x20\x20\x20\x20\x7d\x3b\x0a\x7d\x0a\x66\x6e\x20\x62\x61\x64\x67\x65\x53\x74\x61\x74\x75\x73\x28\x62\x61\x64\x67\x65\x3a\x20\x6d\x2e\x42\x61\x64\x67\x65\x29\x20\x57\x2e\x62\x61\x64\x67\x65\x2e\x42\x61\x64\x67\x65\x53\x74\x61\x74\x75\x73\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x73\x77\x69\x74\x63\x68\x20\x28\x62\x61\x64\x67\x65\x29\x20\x7b\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x2e\x69\x6e\x66\x6f\x20\x3d\x3e\x20\x2e\x69\x6e\x66\x6f\x2c\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x2e\x73\x75\x63\x63\x65\x73\x73\x20\x3d\x3e\x20\x2e\x73\x75\x63\x63\x65\x73\x73\x2c\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x2e\x77\x61\x72\x6e\x69\x6e\x67\x20\x3d\x3e\x20\x2e\x77\x61\x72\x6e\x69\x6e\x67\x2c\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x2e\x40\x22\x65\x72\x72\x6f\x72\x22\x20\x3d\x3e\x20\x2e\x40\x22\x65\x72\x72\x6f\x72\x22\x2c\x0a\x20\x20\x20\x20\x7d\x3b\x0a\x7d\x0a\x66\x6e\x20\x61\x6c\x65\x72\x74\x56\x61\x72\x69\x61\x6e\x74\x28\x77\x61\x72\x6e\x69\x6e\x67\x3a\x20\x62\x6f\x6f\x6c\x29\x20\x57\x2e\x41\x6c\x65\x72\x74\x56\x61\x72\x69\x61\x6e\x74\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x69\x66\x20\x28\x77\x61\x72\x6e\x69\x6e\x67\x29\x20\x2e\x77\x61\x72\x6e\x69\x6e\x67\x20\x65\x6c\x73\x65\x20\x2e\x40\x22\x65\x72\x72\x6f\x72\x22\x3b\x0a\x7d\x0a\x66\x6e\x20\x68\x6f\x70\x49\x63\x6f\x6e\x28\x74\x6f\x6e\x65\x3a\x20\x6d\x2e\x54\x6f\x6e\x65\x29\x20\x75\x69\x2e\x53\x76\x67\x41\x73\x73\x65\x74\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x73\x77\x69\x74\x63\x68\x20\x28\x74\x6f\x6e\x65\x29\x20\x7b\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x2e\x6f\x6b\x20\x3d\x3e\x20\x75\x69\x2e\x69\x63\x6f\x6e\x73\x2e\x63\x68\x65\x63\x6b\x2c\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x2e\x64\x61\x6e\x67\x65\x72\x20\x3d\x3e\x20\x75\x69\x2e\x69\x63\x6f\x6e\x73\x2e\x78\x2c\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x2e\x77\x61\x72\x6e\x69\x6e\x67\x20\x3d\x3e\x20\x75\x69\x2e\x69\x63\x6f\x6e\x73\x2e\x74\x72\x69\x61\x6e\x67\x6c\x65\x5f\x61\x6c\x65\x72\x74\x2c\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x2e\x6d\x75\x74\x65\x64\x20\x3d\x3e\x20\x75\x69\x2e\x69\x63\x6f\x6e\x73\x2e\x63\x69\x72\x63\x6c\x65\x5f\x64\x61\x73\x68\x65\x64\x2c\x0a\x20\x20\x20\x20\x7d\x3b\x0a\x7d\x0a\x66\x6e\x20\x72\x65\x74\x72\x79\x56\x61\x72\x69\x61\x6e\x74\x28\x70\x3a\x20\x6d\x2e\x50\x72\x6f\x6a\x65\x63\x74\x69\x6f\x6e\x29\x20\x57\x2e\x42\x75\x74\x74\x6f\x6e\x56\x61\x72\x69\x61\x6e\x74\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x69\x66\x20\x28\x70\x2e\x70\x72\x69\x6d\x61\x72\x79\x20\x3d\x3d\x20\x2e\x72\x65\x74\x72\x79\x5f\x6e\x6f\x77\x29\x20\x2e\x70\x72\x69\x6d\x61\x72\x79\x20\x65\x6c\x73\x65\x20\x2e\x73\x65\x63\x6f\x6e\x64\x61\x72\x79\x3b\x0a\x7d\x0a\x0a\x66\x6e\x20\x48\x6f\x70\x52\x6f\x77\x28\x68\x6f\x70\x3a\x20\x6d\x2e\x48\x6f\x70\x52\x6f\x77\x2c\x20\x69\x6e\x64\x65\x78\x3a\x20\x75\x73\x69\x7a\x65\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x72\x6f\x77\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x69\x64\x73\x2e\x68\x6f\x70\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x68\x6f\x70\x5f\x72\x6f\x77\x7d\x20\x61\x31\x31\x79\x3d\x7b\x2e\x7b\x20\x2e\x72\x6f\x6c\x65\x20\x3d\x20\x2e\x6c\x69\x73\x74\x69\x74\x65\x6d\x2c\x20\x2e\x6c\x61\x62\x65\x6c\x20\x3d\x20\x68\x6f\x70\x2e\x6e\x61\x6d\x65\x2c\x20\x2e\x76\x61\x6c\x75\x65\x5f\x74\x65\x78\x74\x20\x3d\x20\x68\x6f\x70\x2e\x73\x74\x61\x74\x75\x73\x20\x7d\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x4d\x61\x72\x6b\x65\x72\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x74\x6f\x6e\x65\x20\x3d\x20\x74\x6f\x6e\x65\x4f\x66\x28\x53\x2e\x4d\x61\x72\x6b\x65\x72\x54\x6f\x6e\x65\x2c\x20\x68\x6f\x70\x2e\x74\x6f\x6e\x65\x29\x20\x7d\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x69\x63\x6f\x6e\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x4d\x61\x72\x6b\x65\x72\x49\x63\x6f\x6e\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x74\x6f\x6e\x65\x20\x3d\x20\x74\x6f\x6e\x65\x4f\x66\x28\x53\x2e\x4d\x61\x72\x6b\x65\x72\x49\x63\x6f\x6e\x54\x6f\x6e\x65\x2c\x20\x68\x6f\x70\x2e\x74\x6f\x6e\x65\x29\x20\x7d\x29\x7d\x20\x73\x72\x63\x3d\x7b\x68\x6f\x70\x49\x63\x6f\x6e\x28\x68\x6f\x70\x2e\x74\x6f\x6e\x65\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x63\x6f\x6c\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x68\x6f\x70\x5f\x74\x65\x78\x74\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x68\x6f\x70\x5f\x6e\x61\x6d\x65\x7d\x3e\x7b\x68\x6f\x70\x2e\x6e\x61\x6d\x65\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x68\x6f\x70\x5f\x61\x64\x64\x72\x65\x73\x73\x7d\x3e\x7b\x68\x6f\x70\x2e\x61\x64\x64\x72\x65\x73\x73\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x48\x6f\x70\x53\x74\x61\x74\x75\x73\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x74\x6f\x6e\x65\x20\x3d\x20\x74\x6f\x6e\x65\x4f\x66\x28\x53\x2e\x48\x6f\x70\x53\x74\x61\x74\x75\x73\x54\x6f\x6e\x65\x2c\x20\x68\x6f\x70\x2e\x74\x6f\x6e\x65\x29\x20\x7d\x29\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x66\x69\x78\x65\x64\x5f\x62\x6f\x78\x7d\x3e\x7b\x68\x6f\x70\x2e\x73\x74\x61\x74\x75\x73\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x72\x6f\x77\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x70\x75\x62\x20\x66\x6e\x20\x43\x6f\x6e\x6e\x65\x63\x74\x69\x6f\x6e\x46\x61\x69\x6c\x75\x72\x65\x28\x76\x6d\x3a\x20\x2a\x43\x2e\x46\x61\x69\x6c\x75\x72\x65\x56\x69\x65\x77\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x69\x64\x73\x2e\x72\x6f\x6f\x74\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x75\x72\x66\x61\x63\x65\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x76\x6d\x2e\x73\x68\x6f\x77\x6e\x28\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x63\x6f\x6c\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x63\x6f\x6c\x75\x6d\x6e\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x72\x6f\x77\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x68\x65\x61\x64\x65\x72\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x69\x63\x6f\x6e\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x48\x65\x61\x64\x49\x63\x6f\x6e\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x74\x6f\x6e\x65\x20\x3d\x20\x68\x65\x61\x64\x54\x6f\x6e\x65\x28\x76\x6d\x2e\x70\x28\x29\x2e\x69\x63\x6f\x6e\x29\x20\x7d\x29\x7d\x20\x73\x72\x63\x3d\x7b\x68\x65\x61\x64\x49\x63\x6f\x6e\x28\x76\x6d\x2e\x70\x28\x29\x2e\x69\x63\x6f\x6e\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6e\x61\x6d\x65\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x6e\x61\x6d\x65\x5f\x62\x6f\x78\x7d\x3e\x7b\x76\x6d\x2e\x70\x28\x29\x2e\x6e\x61\x6d\x65\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x65\x6e\x64\x70\x6f\x69\x6e\x74\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x65\x6e\x64\x70\x6f\x69\x6e\x74\x5f\x62\x6f\x78\x7d\x3e\x7b\x76\x6d\x2e\x70\x28\x29\x2e\x65\x6e\x64\x70\x6f\x69\x6e\x74\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x73\x70\x61\x63\x65\x72\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x53\x74\x61\x74\x75\x73\x42\x61\x64\x67\x65\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x69\x64\x73\x2e\x62\x61\x64\x67\x65\x7d\x20\x73\x74\x61\x74\x75\x73\x3d\x7b\x62\x61\x64\x67\x65\x53\x74\x61\x74\x75\x73\x28\x76\x6d\x2e\x70\x28\x29\x2e\x62\x61\x64\x67\x65\x29\x7d\x20\x6c\x61\x62\x65\x6c\x3d\x7b\x76\x6d\x2e\x70\x28\x29\x2e\x62\x61\x64\x67\x65\x5f\x74\x65\x78\x74\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x72\x6f\x77\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x69\x64\x73\x2e\x74\x69\x74\x6c\x65\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x74\x69\x74\x6c\x65\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x66\x69\x6c\x6c\x5f\x62\x6f\x78\x7d\x20\x61\x31\x31\x79\x3d\x7b\x2e\x7b\x20\x2e\x72\x6f\x6c\x65\x20\x3d\x20\x2e\x68\x65\x61\x64\x69\x6e\x67\x20\x7d\x7d\x3e\x7b\x76\x6d\x2e\x70\x28\x29\x2e\x74\x69\x74\x6c\x65\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x41\x6c\x65\x72\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x69\x64\x73\x2e\x61\x6c\x65\x72\x74\x7d\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x61\x6c\x65\x72\x74\x56\x61\x72\x69\x61\x6e\x74\x28\x76\x6d\x2e\x70\x28\x29\x2e\x61\x6c\x65\x72\x74\x5f\x77\x61\x72\x6e\x69\x6e\x67\x29\x7d\x20\x74\x69\x74\x6c\x65\x3d\x7b\x76\x6d\x2e\x70\x28\x29\x2e\x61\x6c\x65\x72\x74\x5f\x74\x69\x74\x6c\x65\x7d\x20\x6d\x65\x73\x73\x61\x67\x65\x3d\x7b\x76\x6d\x2e\x70\x28\x29\x2e\x61\x6c\x65\x72\x74\x5f\x64\x65\x74\x61\x69\x6c\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x63\x6f\x6c\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x69\x64\x73\x2e\x72\x65\x74\x72\x79\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x72\x65\x74\x72\x79\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x76\x6d\x2e\x70\x28\x29\x2e\x72\x65\x74\x72\x79\x5f\x73\x68\x6f\x77\x6e\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x72\x6f\x77\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6e\x6f\x74\x65\x5f\x72\x6f\x77\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x69\x63\x6f\x6e\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6e\x6f\x74\x65\x5f\x69\x63\x6f\x6e\x7d\x20\x73\x72\x63\x3d\x7b\x75\x69\x2e\x69\x63\x6f\x6e\x73\x2e\x72\x65\x66\x72\x65\x73\x68\x5f\x63\x77\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6e\x6f\x74\x65\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x67\x72\x6f\x77\x5f\x62\x6f\x78\x7d\x3e\x7b\x76\x6d\x2e\x70\x28\x29\x2e\x72\x65\x74\x72\x79\x5f\x74\x65\x78\x74\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x72\x6f\x77\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x69\x64\x73\x2e\x72\x65\x74\x72\x79\x5f\x62\x61\x72\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x62\x61\x72\x7d\x3e\x3c\x57\x2e\x50\x72\x6f\x67\x72\x65\x73\x73\x20\x76\x61\x6c\x75\x65\x3d\x7b\x76\x6d\x2e\x70\x28\x29\x2e\x72\x65\x74\x72\x79\x5f\x70\x65\x72\x63\x65\x6e\x74\x7d\x20\x68\x65\x69\x67\x68\x74\x3d\x7b\x34\x7d\x20\x73\x77\x65\x65\x70\x3d\x7b\x2e\x66\x6c\x61\x74\x7d\x20\x2f\x3e\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x72\x6f\x77\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x69\x64\x73\x2e\x68\x6f\x6c\x64\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6e\x6f\x74\x65\x5f\x72\x6f\x77\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x76\x6d\x2e\x68\x6f\x6c\x64\x53\x68\x6f\x77\x6e\x28\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x69\x63\x6f\x6e\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6e\x6f\x74\x65\x5f\x69\x63\x6f\x6e\x7d\x20\x73\x72\x63\x3d\x7b\x75\x69\x2e\x69\x63\x6f\x6e\x73\x2e\x70\x61\x75\x73\x65\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6e\x6f\x74\x65\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x67\x72\x6f\x77\x5f\x62\x6f\x78\x7d\x3e\x7b\x76\x6d\x2e\x70\x28\x29\x2e\x68\x6f\x6c\x64\x5f\x74\x65\x78\x74\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x72\x6f\x77\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x63\x6f\x6c\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6b\x65\x79\x73\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x76\x6d\x2e\x70\x28\x29\x2e\x68\x6f\x73\x74\x5f\x6b\x65\x79\x5f\x73\x68\x6f\x77\x6e\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x63\x6f\x6c\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x69\x64\x73\x2e\x73\x61\x76\x65\x64\x5f\x6b\x65\x79\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6b\x65\x79\x5f\x62\x6c\x6f\x63\x6b\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6b\x65\x79\x5f\x74\x69\x74\x6c\x65\x7d\x3e\x7b\x76\x6d\x2e\x70\x28\x29\x2e\x73\x61\x76\x65\x64\x5f\x6b\x65\x79\x5f\x74\x69\x74\x6c\x65\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6b\x65\x79\x5f\x76\x61\x6c\x75\x65\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x66\x69\x6c\x6c\x5f\x62\x6f\x78\x7d\x3e\x7b\x76\x6d\x2e\x70\x28\x29\x2e\x73\x61\x76\x65\x64\x5f\x6b\x65\x79\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x63\x6f\x6c\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x69\x64\x73\x2e\x6f\x66\x66\x65\x72\x65\x64\x5f\x6b\x65\x79\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6b\x65\x79\x5f\x62\x6c\x6f\x63\x6b\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6b\x65\x79\x5f\x74\x69\x74\x6c\x65\x7d\x3e\x7b\x76\x6d\x2e\x70\x28\x29\x2e\x6f\x66\x66\x65\x72\x65\x64\x5f\x6b\x65\x79\x5f\x74\x69\x74\x6c\x65\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6b\x65\x79\x5f\x76\x61\x6c\x75\x65\x5f\x63\x68\x61\x6e\x67\x65\x64\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x66\x69\x6c\x6c\x5f\x62\x6f\x78\x7d\x3e\x7b\x76\x6d\x2e\x70\x28\x29\x2e\x6f\x66\x66\x65\x72\x65\x64\x5f\x6b\x65\x79\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x63\x6f\x6c\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x69\x64\x73\x2e\x72\x6f\x75\x74\x65\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x72\x6f\x75\x74\x65\x7d\x20\x61\x31\x31\x79\x3d\x7b\x2e\x7b\x20\x2e\x72\x6f\x6c\x65\x20\x3d\x20\x2e\x6c\x69\x73\x74\x2c\x20\x2e\x6c\x61\x62\x65\x6c\x20\x3d\x20\x76\x6d\x2e\x70\x28\x29\x2e\x72\x6f\x75\x74\x65\x20\x7d\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x72\x6f\x75\x74\x65\x5f\x6c\x61\x62\x65\x6c\x7d\x3e\x7b\x76\x6d\x2e\x70\x28\x29\x2e\x72\x6f\x75\x74\x65\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x7b\x66\x6f\x72\x20\x28\x76\x6d\x2e\x70\x28\x29\x2e\x68\x6f\x70\x73\x29\x20\x7c\x68\x6f\x70\x2c\x20\x69\x7c\x20\x3c\x48\x6f\x70\x52\x6f\x77\x20\x6b\x65\x79\x3d\x7b\x68\x6f\x70\x2e\x6b\x65\x79\x7d\x20\x68\x6f\x70\x3d\x7b\x68\x6f\x70\x7d\x20\x69\x6e\x64\x65\x78\x3d\x7b\x69\x7d\x20\x2f\x3e\x7d\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x63\x6f\x6c\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x69\x64\x73\x2e\x6c\x6f\x67\x73\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6c\x6f\x67\x73\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x76\x6d\x2e\x70\x28\x29\x2e\x6c\x6f\x67\x73\x5f\x6f\x70\x65\x6e\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x7b\x66\x6f\x72\x20\x28\x76\x6d\x2e\x6c\x6f\x67\x4c\x69\x6e\x65\x73\x28\x29\x29\x20\x7c\x6c\x69\x6e\x65\x7c\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6c\x6f\x67\x5f\x6c\x69\x6e\x65\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x66\x69\x6c\x6c\x5f\x62\x6f\x78\x7d\x3e\x7b\x6c\x69\x6e\x65\x2e\x74\x65\x78\x74\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x7d\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x72\x6f\x77\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x61\x63\x74\x69\x6f\x6e\x73\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x69\x64\x73\x2e\x65\x64\x69\x74\x7d\x20\x6c\x61\x62\x65\x6c\x3d\x22\xe7\xbc\x96\xe8\xbe\x91\xe4\xb8\xbb\xe6\x9c\xba\x22\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x73\x65\x63\x6f\x6e\x64\x61\x72\x79\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x76\x6d\x2e\x70\x28\x29\x2e\x63\x61\x6e\x5f\x65\x64\x69\x74\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x73\x65\x6e\x64\x28\x76\x6d\x2c\x20\x2e\x65\x64\x69\x74\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x69\x64\x73\x2e\x6c\x6f\x67\x73\x5f\x74\x6f\x67\x67\x6c\x65\x7d\x20\x6c\x61\x62\x65\x6c\x3d\x7b\x76\x6d\x2e\x70\x28\x29\x2e\x6c\x6f\x67\x73\x5f\x6c\x61\x62\x65\x6c\x7d\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x67\x68\x6f\x73\x74\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x76\x6d\x2e\x6c\x6f\x67\x73\x44\x69\x73\x61\x62\x6c\x65\x64\x28\x29\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x73\x65\x6e\x64\x28\x76\x6d\x2c\x20\x2e\x74\x6f\x67\x67\x6c\x65\x5f\x6c\x6f\x67\x73\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x73\x70\x61\x63\x65\x72\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x69\x64\x73\x2e\x73\x74\x6f\x70\x5f\x72\x65\x74\x72\x79\x7d\x20\x6c\x61\x62\x65\x6c\x3d\x22\xe5\x81\x9c\xe6\xad\xa2\xe9\x87\x8d\xe8\xaf\x95\x22\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x67\x68\x6f\x73\x74\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x76\x6d\x2e\x70\x28\x29\x2e\x73\x74\x6f\x70\x5f\x72\x65\x74\x72\x79\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x73\x65\x6e\x64\x28\x76\x6d\x2c\x20\x2e\x73\x74\x6f\x70\x5f\x72\x65\x74\x72\x79\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x69\x64\x73\x2e\x64\x69\x73\x63\x6f\x6e\x6e\x65\x63\x74\x7d\x20\x6c\x61\x62\x65\x6c\x3d\x22\xe6\x96\xad\xe5\xbc\x80\x22\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x67\x68\x6f\x73\x74\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x76\x6d\x2e\x70\x28\x29\x2e\x64\x69\x73\x63\x6f\x6e\x6e\x65\x63\x74\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x73\x65\x6e\x64\x28\x76\x6d\x2c\x20\x2e\x64\x69\x73\x63\x6f\x6e\x6e\x65\x63\x74\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x69\x64\x73\x2e\x72\x65\x74\x72\x79\x5f\x6e\x6f\x77\x7d\x20\x6c\x61\x62\x65\x6c\x3d\x22\xe7\xab\x8b\xe5\x8d\xb3\xe9\x87\x8d\xe8\xaf\x95\x22\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x72\x65\x74\x72\x79\x56\x61\x72\x69\x61\x6e\x74\x28\x76\x6d\x2e\x70\x28\x29\x29\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x76\x6d\x2e\x70\x28\x29\x2e\x72\x65\x74\x72\x79\x5f\x6e\x6f\x77\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x76\x6d\x2e\x70\x28\x29\x2e\x72\x65\x74\x72\x79\x5f\x64\x69\x73\x61\x62\x6c\x65\x64\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x73\x65\x6e\x64\x28\x76\x6d\x2c\x20\x2e\x72\x65\x74\x72\x79\x5f\x6e\x6f\x77\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x69\x64\x73\x2e\x63\x72\x65\x64\x65\x6e\x74\x69\x61\x6c\x73\x7d\x20\x6c\x61\x62\x65\x6c\x3d\x22\xe9\x87\x8d\xe6\x96\xb0\xe8\xbe\x93\xe5\x85\xa5\xe5\x87\xad\xe6\x8d\xae\x22\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x70\x72\x69\x6d\x61\x72\x79\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x76\x6d\x2e\x70\x28\x29\x2e\x63\x72\x65\x64\x65\x6e\x74\x69\x61\x6c\x73\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x73\x65\x6e\x64\x28\x76\x6d\x2c\x20\x2e\x63\x72\x65\x64\x65\x6e\x74\x69\x61\x6c\x73\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x69\x64\x73\x2e\x74\x72\x75\x73\x74\x5f\x6b\x65\x79\x7d\x20\x6c\x61\x62\x65\x6c\x3d\x7b\x72\x65\x70\x6c\x61\x63\x65\x5f\x6b\x65\x79\x7d\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x64\x61\x6e\x67\x65\x72\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x76\x6d\x2e\x70\x28\x29\x2e\x74\x72\x75\x73\x74\x5f\x6b\x65\x79\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x73\x65\x6e\x64\x28\x76\x6d\x2c\x20\x2e\x74\x72\x75\x73\x74\x5f\x6b\x65\x79\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x72\x6f\x77\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x43\x6f\x6e\x66\x69\x72\x6d\x44\x69\x61\x6c\x6f\x67\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x69\x64\x73\x2e\x74\x72\x75\x73\x74\x5f\x63\x6f\x6e\x66\x69\x72\x6d\x7d\x20\x6f\x70\x65\x6e\x3d\x7b\x74\x72\x75\x73\x74\x4f\x70\x65\x6e\x28\x76\x6d\x29\x7d\x20\x74\x69\x74\x6c\x65\x3d\x22\xe6\x9b\xbf\xe6\x8d\xa2\xe4\xb8\xbb\xe6\x9c\xba\xe5\xaf\x86\xe9\x92\xa5\xef\xbc\x9f\x22\x20\x6d\x65\x73\x73\x61\x67\x65\x3d\x22\xe6\x9c\x8d\xe5\x8a\xa1\xe5\x99\xa8\xe5\xbd\x93\xe5\x89\x8d\xe6\x8f\x90\xe4\xbe\x9b\xe7\x9a\x84\xe5\xaf\x86\xe9\x92\xa5\xe4\xb8\x8e\xe5\xb7\xb2\xe4\xbf\x9d\xe5\xad\x98\xe7\x9a\x84\xe4\xb8\x8d\xe5\x90\x8c\xe3\x80\x82\xe6\x9b\xbf\xe6\x8d\xa2\xe4\xbc\x9a\xe8\xa6\x86\xe7\x9b\x96\xe5\xb7\xb2\xe4\xbf\x9d\xe5\xad\x98\xe7\x9a\x84\xe5\xaf\x86\xe9\x92\xa5\xe5\xb9\xb6\xe7\x94\xa8\xe6\x96\xb0\xe5\xaf\x86\xe9\x92\xa5\xe7\xbb\xa7\xe7\xbb\xad\xe8\xbf\x9e\xe6\x8e\xa5\xef\xbc\x9b\xe8\xaf\xb7\xe5\x85\x88\xe6\xa0\xb8\xe5\xaf\xb9\xe6\x96\xb0\xe6\x8c\x87\xe7\xba\xb9\xef\xbc\x8c\xe7\xa1\xae\xe8\xae\xa4\xe6\x9c\x8d\xe5\x8a\xa1\xe5\x99\xa8\xe7\xa1\xae\xe5\xae\x9e\xe6\x9b\xb4\xe6\x8d\xa2\xe8\xbf\x87\xe5\xaf\x86\xe9\x92\xa5\xe3\x80\x82\x22\x20\x63\x6f\x6e\x66\x69\x72\x6d\x4c\x61\x62\x65\x6c\x3d\x7b\x72\x65\x70\x6c\x61\x63\x65\x5f\x6b\x65\x79\x7d\x20\x63\x61\x6e\x63\x65\x6c\x4c\x61\x62\x65\x6c\x3d\x7b\x43\x6f\x6e\x66\x69\x72\x6d\x2e\x63\x61\x6e\x63\x65\x6c\x5f\x6c\x61\x62\x65\x6c\x7d\x20\x63\x6c\x6f\x73\x65\x4f\x6e\x4f\x76\x65\x72\x6c\x61\x79\x3d\x7b\x43\x6f\x6e\x66\x69\x72\x6d\x2e\x63\x6c\x6f\x73\x65\x5f\x6f\x6e\x5f\x6f\x76\x65\x72\x6c\x61\x79\x7d\x20\x6f\x6e\x43\x6f\x6e\x66\x69\x72\x6d\x3d\x7b\x74\x72\x75\x73\x74\x43\x6f\x6e\x66\x69\x72\x6d\x65\x64\x28\x76\x6d\x29\x7d\x20\x6f\x6e\x43\x61\x6e\x63\x65\x6c\x3d\x7b\x74\x72\x75\x73\x74\x43\x61\x6e\x63\x65\x6c\x6c\x65\x64\x28\x76\x6d\x29\x7d\x20\x74\x65\x73\x74\x49\x64\x73\x3d\x7b\x2e\x7b\x20\x2e\x63\x61\x6e\x63\x65\x6c\x20\x3d\x20\x69\x64\x73\x2e\x74\x72\x75\x73\x74\x5f\x63\x6f\x6e\x66\x69\x72\x6d\x5f\x63\x61\x6e\x63\x65\x6c\x2c\x20\x2e\x63\x6f\x6e\x66\x69\x72\x6d\x20\x3d\x20\x69\x64\x73\x2e\x74\x72\x75\x73\x74\x5f\x63\x6f\x6e\x66\x69\x72\x6d\x5f\x61\x63\x63\x65\x70\x74\x20\x7d\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a" else null;
const __YixStyleCatalog = if (ui.view.template.preview_enabled) ui.view.template.styleCatalog(.{ .@"S " = S, .@"ids . root " = ids.root, .@"ids . badge " = ids.badge, .@"ids . title " = ids.title, .@"ids . alert " = ids.alert, .@"ids . retry " = ids.retry, .@"ids . retry_bar " = ids.retry_bar, .@"ids . hold " = ids.hold, .@"ids . saved_key " = ids.saved_key, .@"ids . offered_key " = ids.offered_key, .@"ids . route " = ids.route, .@"ids . hop " = ids.hop, .@"ids . logs " = ids.logs, .@"ids . edit " = ids.edit, .@"ids . logs_toggle " = ids.logs_toggle, .@"ids . stop_retry " = ids.stop_retry, .@"ids . retry_now " = ids.retry_now, .@"ids . credentials " = ids.credentials, .@"ids . disconnect " = ids.disconnect, .@"ids . trust_key " = ids.trust_key, .@"ids . trust_confirm " = ids.trust_confirm, .@"ids . trust_confirm_cancel " = ids.trust_confirm_cancel, .@"ids . trust_confirm_accept " = ids.trust_confirm_accept, .@"replace_key " = replace_key, }) else void;

//# yix-map-data [[4717,4712],[13903,5455]]

//# yix-map connection_failure.yix
