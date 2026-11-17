//! 测试卡片 `fixture.float` 内容的视图模型（float-split）：文字、选中行。滚动位置在原生 ScrollArea 自己的
//! 状态里，随内容节点一起搬动。
const std = @import("std");
const ui = @import("ui");
const W = ui.widgets;
const model = @import("../model/float_fixture.zig");
const template = @import("_float_fixture.yix.zig");

pub const Row = struct { index: usize, label: []const u8, test_id: []const u8 };

pub const Vm = struct {
    rows: []const Row,
    text_signal: *ui.Signal([]const u8),
    selected: *ui.Signal(usize),
    text_buffers: [2][256]u8 = undefined,
    text_slot: u1 = 0,
    selection_buffer: [48]u8 = undefined,

    pub fn text(self: *const Vm) []const u8 {
        return self.text_signal.get();
    }
    pub fn edit(self: *Vm, value: []const u8) void {
        self.text_slot +%= 1;
        const buffer = &self.text_buffers[self.text_slot];
        const n = @min(value.len, buffer.len);
        @memcpy(buffer[0..n], value[0..n]);
        self.text_signal.set(buffer[0..n]);
    }
    pub fn selectionText(self: *Vm) []const u8 {
        const index = self.selected.get();
        if (index >= self.rows.len) return "未选中";
        return std.fmt.bufPrint(&self.selection_buffer, "已选：{s}", .{self.rows[index].label}) catch "";
    }
    pub fn rowVariant(self: *const Vm, index: usize) W.ButtonVariant {
        return if (self.selected.get() == index) .secondary else .ghost;
    }
    pub fn select(self: *Vm, index: usize) void {
        self.selected.set(index);
    }
};

const Labels = struct {
    var labels: [model.row_count][24]u8 = undefined;
    var ids: [model.row_count][40]u8 = undefined;
    var rows: [model.row_count]Row = undefined;
    var ready = false;
    fn get() []const Row {
        if (!ready) {
            for (&rows, 0..) |*row, index| {
                const label = std.fmt.bufPrint(&labels[index], "第 {d} 行", .{index + 1}) catch unreachable;
                const id = std.fmt.bufPrint(&ids[index], "fixture.float.row.{d}", .{index + 1}) catch unreachable;
                row.* = .{ .index = index, .label = label, .test_id = id };
            }
            ready = true;
        }
        return &rows;
    }
};

pub const Content = struct {
    vm: Vm,
    root: *ui.Node = undefined,

    pub fn mount(cx: *ui.Cx, scope: *ui.Scope) !*Content {
        const self = try scope.createState(Content, .{ .vm = .{ .rows = Labels.get(), .text_signal = try scope.createSignal([]const u8, ""), .selected = try scope.createSignal(usize, std.math.maxInt(usize)) } });
        self.root = try ui.view.render(scope, cx, template.FixtureCard(.{ .vm = &self.vm }));
        return self;
    }
};
