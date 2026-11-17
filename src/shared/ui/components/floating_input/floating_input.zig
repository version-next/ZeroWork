//! Input boundary for one of ZeroWork's own in-tree floating surfaces: the surface that creates
//! it calls `protect` on its own node. zenit's overlay layers (Popover, Menu, Modal, Tooltip)
//! need nothing from here: their content and barriers take pointer and wheel themselves.
const ui = @import("ui");

pub fn protect(cx: *ui.Cx, node: *ui.Node) void {
    if (node.style.hit_behavior() == .pass_through) return;
    if (node.behavior.interaction.a11y) |a11y| if (a11y.role == .tooltip) return;
    const roles = node.style.hit_roles();
    if (roles.pointer != true or roles.scroll != true or node.style.hit_behavior() != .@"opaque") {
        node.setStyleInline(cx.allocator, .{ .hit_behavior = .@"opaque", .hit_roles = .{ .pointer = true, .scroll = true } });
    }
    // Child buttons/inputs/ScrollAreas handle their own events first. Blank
    // chrome and exhausted inner scrolling stop here, before a terminal parent.
    if (node.behavior.events.on_event == null) node.behavior.events.on_event = consumeInput;
    if (node.behavior.events.on_scroll == null) node.behavior.events.on_scroll = consumeScroll;
}

fn consumeInput(event: ui.events.Event, _: ?*anyopaque) ui.events.EventResult {
    return switch (event) {
        .mouse_down, .mouse_up, .click, .double_click, .mouse_move, .scroll => .stop,
        else => .ignored,
    };
}
fn consumeScroll(_: ui.events.ScrollEvent, _: ?*anyopaque) ui.events.EventResult {
    return .stop;
}
