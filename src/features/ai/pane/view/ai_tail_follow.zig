//! Follow new assistant output until the reader deliberately scrolls away.
//!
//! ai-redesign-c（用户拍板新增“新消息”提示，Pencil W1PaA 滚动跟随）：读者上翻离开底部后若来了新回复，记为
//! `unseen`，宿主在输入框上方居中显示原生 Button“新消息”（`hintShown`）。点它 `jumpToEnd`：平滑滚到底（减少动态
//! 效果时直接到底）并恢复跟随；读者自己滚回底部时跟随恢复、提示消失。跟随规则不变（ai-bugs：读者主动滚动才改变
//! 跟随，内容增长从不推断读者意图）。
const std = @import("std");
const ui = @import("ui");

/// The glide back to the end (ease-out, 240 ms).
pub const glide_ms: f64 = 240;

/// Ease-out cubic position between `from` and `to` after `elapsed_ms` of `duration_ms`.
pub fn glidePosition(from: f32, to: f32, elapsed_ms: f64, duration_ms: f64) f32 {
    if (duration_ms <= 0 or elapsed_ms >= duration_ms) return to;
    const t: f32 = @floatCast(@max(0, elapsed_ms / duration_ms));
    const inv = 1 - t;
    const eased = 1 - inv * inv * inv;
    return from + (to - from) * eased;
}

pub const Follow = struct {
    scroll: ui.widgets.ScrollAreaResult,
    following: bool = true,
    input_serial: u64 = 0,
    /// A new reply arrived while the reader was away from the end (the “新消息” hint).
    unseen: bool = false,
    /// The host's reply mark (messages + live output batches) last seen by `noteReplies`.
    reply_mark: usize = 0,
    /// The running glide back to the end (`jumpToEnd`).
    glide: ?struct { from: f32, start_ms: f64 } = null,

    pub fn reset(self: *Follow) void {
        self.following = true;
        self.unseen = false;
        self.glide = null;
        self.input_serial = self.scroll.state.input_serial;
    }
    /// New assistant output (a streaming delta, or more messages than `reply_mark`): unseen while the
    /// reader is away from the end.
    pub fn noteReply(self: *Follow) void {
        if (!self.following) self.unseen = true;
    }
    /// Feed the host's reply mark each frame; any change is new output.
    pub fn noteReplies(self: *Follow, mark: usize, streaming: bool) void {
        if (streaming or mark != self.reply_mark) self.noteReply();
        self.reply_mark = mark;
    }
    /// The “新消息” hint is up.
    pub fn hintShown(self: *const Follow) bool {
        return self.unseen and !self.following;
    }
    /// The hint's click: back to the end (smoothly unless `reduced`) and follow again.
    pub fn jumpToEnd(self: *Follow, now_ms: f64, reduced: bool) void {
        const state = self.scroll.state;
        self.following = true;
        self.unseen = false;
        self.input_serial = state.input_serial;
        if (reduced) {
            self.glide = null;
            ui.widgets.setScrollY(state, self.scroll.content, state.maxScrollY());
        } else self.glide = .{ .from = state.scroll_y, .start_ms = now_ms };
    }
    /// Run after layout; never infer reader intent from content growth.
    pub fn update(self: *Follow) void {
        _ = self.updateAt(null);
    }
    /// `update` with the frame clock for the glide; returns whether the glide still runs (the host keeps
    /// frames coming).
    pub fn updateAt(self: *Follow, now_ms: ?f64) bool {
        const state = self.scroll.state;
        if (state.input_serial != self.input_serial) {
            // The reader scrolled: that decides following (and cancels a glide in flight).
            self.glide = null;
            self.following = state.scroll_y >= state.maxScrollY() - 1;
            if (self.following) self.unseen = false;
            self.input_serial = state.input_serial;
        }
        state.content_height = self.scroll.content.globalRect().h;
        state.viewport_height = self.scroll.container.globalRect().h;
        if (self.glide) |glide| {
            const now = now_ms orelse glide.start_ms + glide_ms;
            const elapsed = now - glide.start_ms;
            ui.widgets.setScrollY(state, self.scroll.content, glidePosition(glide.from, state.maxScrollY(), elapsed, glide_ms));
            if (elapsed >= glide_ms) self.glide = null;
            return self.glide != null;
        }
        if (self.following and @abs(state.scroll_y - state.maxScrollY()) > 0.1) ui.widgets.setScrollY(state, self.scroll.content, state.maxScrollY());
        return false;
    }
};

test "glide eases out from the start to the end" {
    try std.testing.expectEqual(@as(f32, 100), glidePosition(100, 500, 0, glide_ms));
    try std.testing.expectEqual(@as(f32, 500), glidePosition(100, 500, glide_ms, glide_ms));
    try std.testing.expectEqual(@as(f32, 500), glidePosition(100, 500, glide_ms * 2, glide_ms));
    const half = glidePosition(100, 500, glide_ms / 2, glide_ms);
    // Ease-out: past the linear midpoint halfway through.
    try std.testing.expect(half > 300 and half < 500);
}
