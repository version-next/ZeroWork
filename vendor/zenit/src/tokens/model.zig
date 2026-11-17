//! Owned, fully resolved input to the token provider emitter.
const std = @import("std");
pub const values = @import("zenit_style_values");
pub const Category = values.Category;
pub const Scheme = values.ColorScheme;
pub const Value = union(enum) {
    number: f32,
    weight: u16,
    color: values.Color,
    shadow: values.Shadow,
    typography: values.TypographyPatch,
};
pub const Token = struct {
    /// Unified consumption path including category, e.g. color.blue.500.
    path: []const u8,
    /// Authored identity including source layer, e.g. tokens.color.blue.500.
    source_path: []const u8,
    category: Category,
    offset: usize,
    pointer: []const u8,
    /// Index into Document.layers of the file that declared (or last overrode) the token.
    layer: usize = 0,
};
pub const Mode = struct {
    name: []const u8,
    scheme: Scheme,
    /// Index into the final sorted modes array; light has no fallback.
    fallback: ?usize,
    /// One fully resolved value per token, in Document.tokens order.
    values: []const Value,
};
/// One input file of a layered theme, in merge order (base first).
pub const Layer = struct { name: []const u8, source: []const u8 };
/// `offset` is a byte offset into `layers[layer].source`.
pub const Diagnostic = struct { offset: usize, pointer: []const u8, message: []const u8, layer: usize = 0 };
pub const Document = struct {
    arena: std.heap.ArenaAllocator,
    /// First layer source (the only one for a single-file theme).
    source: []const u8 = "",
    layers: []const Layer = &.{},
    tokens: []const Token = &.{},
    modes: []const Mode = &.{},
    diagnostic: ?Diagnostic = null,

    pub fn deinit(self: *Document) void {
        self.arena.deinit();
        self.* = undefined;
    }
};
