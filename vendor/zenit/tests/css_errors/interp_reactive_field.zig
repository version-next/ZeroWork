//! Yix <text>{vm.title}</text> with `vm` a parameter and `title` a *Signal field: the derive yields
//! Source(*Signal([]const u8)); interpolation used to print the signal's struct dump ({any}).
const ui = @import("ui");
test {
    _ = comptime ui.view.yixFormat(ui.Source(*ui.Signal([]const u8)), "");
}
