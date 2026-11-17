//! Standalone composite-document suite; avoids filtered UI aggregator imports.
comptime {
    _ = @import("../model/terminal_document.zig");
    _ = @import("../../history/model/history_cast.zig");
    _ = @import("../../history/model/history_reading.zig");
}
