//! Card scrolling: a card's reading positions (the record's `ScrollPositions`) bound to its native ScrollAreas
//! through their controlled offsets (`scroll_y` / `scroll_x` + `on_scroll_*_change`): a remounted
//! card restores where the reader was, every settled scroll is saved back. No ScrollArea internals,
//! no after-layout hook: the area applies the restored offset once it has a layout and clamps it.
const ui = @import("ui");
const Positions = @import("../../../../ai/tool_results.zig").ScrollPositions;

pub const Slot = Positions.Slot;

pub const Offsets = struct {
    positions: *Positions,
    /// Per slot: the offsets the areas follow (x, y). Writing them scrolls the area there.
    x: [4]*ui.Signal(f32),
    y: [4]*ui.Signal(f32),
    savers: [4]Saver = undefined,

    /// Retains `positions` for the scope's lifetime (the record may go first during a rollback).
    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, positions: *Positions) !*Offsets {
        _ = cx;
        var x: [4]*ui.Signal(f32) = undefined;
        var y: [4]*ui.Signal(f32) = undefined;
        for (positions.offsets, 0..) |offset, index| {
            x[index] = try scope.createSignal(f32, offset.x);
            y[index] = try scope.createSignal(f32, offset.y);
        }
        const self = try scope.createState(Offsets, .{ .positions = positions, .x = x, .y = y });
        for (&self.savers, 0..) |*saver, index| saver.* = .{ .owner = self, .index = index };
        positions.retain();
        try scope.onCleanup(Offsets, self, release);
        return self;
    }

    fn release(self: *Offsets) void {
        self.positions.release();
    }

    /// The vertical offset of `slot` for `ScrollArea(.{ .scroll_y = …, .on_scroll_y_change = … })`.
    pub fn scrollY(self: *Offsets, slot: Slot) *ui.Signal(f32) {
        return self.y[@backingInt(slot)];
    }
    pub fn scrollX(self: *Offsets, slot: Slot) *ui.Signal(f32) {
        return self.x[@backingInt(slot)];
    }
    pub fn onY(self: *Offsets, cx: *ui.Cx, slot: Slot) ui.Handler(f32) {
        return cx.on(Saver, &self.savers[@backingInt(slot)], Saver.y);
    }
    pub fn onX(self: *Offsets, cx: *ui.Cx, slot: Slot) ui.Handler(f32) {
        return cx.on(Saver, &self.savers[@backingInt(slot)], Saver.x);
    }

    /// Another target is shown: its body and output start at the top again.
    pub fn resetTarget(self: *Offsets) void {
        for ([_]Slot{ .body, .stdout, .stderr }) |slot| {
            const index = @backingInt(slot);
            self.positions.offsets[index] = .{};
            self.x[index].set(0);
            self.y[index].set(0);
        }
    }

    const Saver = struct {
        owner: *Offsets,
        index: usize,
        fn x(self: *Saver, value: f32) void {
            self.owner.positions.offsets[self.index].x = value;
        }
        fn y(self: *Saver, value: f32) void {
            self.owner.positions.offsets[self.index].y = value;
        }
    };
};
