//! Browser clipboard for the Web DOM host. Writes go straight to
//! navigator.clipboard (inside the key gesture); reads come from a mirror the
//! JS side fills from the `paste` event before forwarding ⌘V/Ctrl+V to zenit
//! (the async Clipboard API cannot be read synchronously).
const std = @import("std");
extern "zenit" fn clipboard_write(ptr: [*]const u8, len: usize) void;

var mirror: std.ArrayListUnmanaged(u8) = .empty;

pub fn setText(text: []const u8) bool {
    clipboard_write(text.ptr, text.len);
    setMirror(text);
    return true;
}

pub fn setMirror(text: []const u8) void {
    mirror.clearRetainingCapacity();
    mirror.appendSlice(std.heap.wasm_allocator, text) catch {};
}

pub fn getText() ?[]const u8 {
    return if (mirror.items.len == 0) null else mirror.items;
}
