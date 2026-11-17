//! StyleDecl: the properties one layer (recipe, state condition, component inline,
//! caller override) declares for the current theme, and their values.
//!
//! Same information as the write-form (BoxStyle literal: 76 optional fields, 1120
//! bytes) but only declared fields are stored: a bitset tracks which have values,
//! values are packed by field index in a byte region. Undeclared fields take no space.
//!
//! State, not change: differences between two evaluations are computed from the
//! post-cascade target (ComputedStyle). "No longer declaring X" = not in the new
//! declaration; the cascade falls through to a lower layer / default.
//!
//! Three storage forms:
//! - `inline_bytes`: small runtime values stored inside the declaration, with no
//!   allocation; copying a declaration copies these bytes.
//! - `packed`: runtime encoding; byte region owned by the caller's allocator (scope /
//!   theme generation cache), immutable.
//! - `dense`: points to a write-form constant (compile-time literal, shared),
//!   bitset computed at compile time.
//! Equality: same compile-time constant -> equal; else compare bitsets, then each
//! common field value (exact float comparison, not whole-region byte compare).
//!
//! Ownership: StyleDecl is a small value (copy freely); all copies share one byte
//! region for heap-backed declarations, freed by its owner with the encoding
//! allocator. After that free, heap-backed copies must not be read or compared.
//! Inline declarations own their bytes by value and need no allocator lifetime.
const std = @import("std");

/// Sparse declaration of `S`. Requires: S is struct, all fields optional, all
/// fields fixed-size (no pointers/slices).
pub fn StyleDecl(comptime S: type) type {
    const fields = @import("zenit_reflection").fields(S);
    comptime {
        @setEvalBranchQuota(20000);
        if (@typeInfo(S) != .@"struct") @compileError("StyleDecl: " ++ @typeName(S) ++ " is not a struct");
        if (fields.len > 128) @compileError("StyleDecl: more than 128 fields");
        for (fields) |f| {
            if (@typeInfo(f.type) != .optional) @compileError("StyleDecl: field " ++ f.name ++ " of " ++ @typeName(S) ++ " must be optional");
            assertFixedSize(@typeInfo(f.type).optional.child, f.name);
        }
        // Bitset bit order = field enum index = field index: compute bits by index,
        // read by enum; must be consistent.
        for (fields, 0..) |f, i| {
            if (@backingInt(@field(std.meta.FieldEnum(S), f.name)) != i) @compileError("StyleDecl: field enum order differs from field order");
        }
    }
    return struct {
        mask: Mask = 0,
        store: Store = .{ .packed_bytes = &.{} },

        const Self = @This();
        pub const Style = S;
        pub const Mask = u128;
        pub const Field = std.meta.FieldEnum(S);

        // Match the existing slice payload on each target (16 bytes on 64-bit).
        const inline_capacity = @sizeOf([]const u8);
        const InlineBytes = struct { bytes: [inline_capacity]u8, len: u8 };

        const Store = union(enum) {
            inline_bytes: InlineBytes,
            /// Runtime encoding: values compacted by field index (raw bytes; read copies into
            /// aligned local variables).
            packed_bytes: []const u8,
            /// Write-form constant.
            dense: *const S,
        };

        /// Byte count for each field value (without optional wrapper).
        const sizes = blk: {
            var s: [fields.len]usize = undefined;
            for (fields, 0..) |f, i| s[i] = @sizeOf(@typeInfo(f.type).optional.child);
            break :blk s;
        };

        fn bit(comptime i: usize) Mask {
            return @as(Mask, 1) << @intCast(i);
        }

        fn ValueOf(comptime f: Field) type {
            return @typeInfo(@FieldType(S, @tagName(f))).optional.child;
        }

        /// Count of declared fields.
        pub fn count(self: Self) usize {
            return @popCount(self.mask);
        }

        pub fn isEmpty(self: Self) bool {
            return self.mask == 0;
        }

        pub fn has(self: Self, comptime f: Field) bool {
            return self.mask & bit(@backingInt(f)) != 0;
        }

        /// Field offset in byte region: sum of sizes of fields with lower indices in bitset.
        fn offsetOf(mask: Mask, index: usize) usize {
            var m = mask & ((@as(Mask, 1) << @intCast(index)) - 1);
            var off: usize = 0;
            while (m != 0) : (m &= m - 1) off += sizes[@ctz(m)];
            return off;
        }

        /// Bytes needed for encoding.
        fn byteLen(mask: Mask) usize {
            var m = mask;
            var n: usize = 0;
            while (m != 0) : (m &= m - 1) n += sizes[@ctz(m)];
            return n;
        }

        // The pointer receiver ties an inline slice to the caller's declaration,
        // never to a temporary copy returned from this helper.
        fn packedBytes(self: *const Self) []const u8 {
            return switch (self.store) {
                .inline_bytes => |*small| small.bytes[0..small.len],
                .packed_bytes => |bytes| bytes,
                .dense => unreachable,
            };
        }

        pub fn get(self: Self, comptime f: Field) ?ValueOf(f) {
            if (!self.has(f)) return null;
            if (self.store == .dense) return @field(self.store.dense.*, @tagName(f));
            const bytes = self.packedBytes();
            const i = @backingInt(f);
            const off = offsetOf(self.mask, i);
            var v: ValueOf(f) = undefined;
            @memcpy(std.mem.asBytes(&v), bytes[off..][0..sizes[i]]);
            return v;
        }

        /// Bit of one field in `mask`.
        pub fn fieldBit(comptime f: Field) Mask {
            return bit(@backingInt(f));
        }

        /// Which fields a write-form value declares (the mask `encode` would give it).
        pub fn maskOf(s: *const S) Mask {
            var mask: Mask = 0;
            inline for (fields, 0..) |f, i| {
                if (@field(s.*, f.name) != null) mask |= bit(i);
            }
            return mask;
        }

        /// Each field in `subset` (all declared here) has `s`'s value (`valueEql`), in one pass
        /// over the byte region; no decode of the other fields.
        pub fn eqlFields(self: *const Self, s: *const S, subset: Mask) bool {
            std.debug.assert(subset & ~self.mask == 0);
            if (subset == 0) return true;
            if (self.store == .dense) {
                inline for (fields, 0..) |f, i| {
                    if (subset & bit(i) != 0 and !valueEql(@field(self.store.dense.*, f.name), @field(s.*, f.name))) return false;
                }
                return true;
            }
            const bytes = self.packedBytes();
            // Visit the declared fields only (in index order, accumulating their offsets), up to
            // the last one in `subset`; each compared field's value is read through a jump table
            // on its index rather than testing every field of S.
            var off: usize = 0;
            var m = self.mask;
            while (m != 0) : (m &= m - 1) {
                const i = @ctz(m);
                const b = @as(Mask, 1) << @intCast(i);
                if (subset & b != 0) {
                    switch (i) {
                        inline 0...fields.len - 1 => |ci| {
                            const f = fields[ci];
                            const want = @field(s.*, f.name) orelse return false;
                            var v: @typeInfo(f.type).optional.child = undefined;
                            @memcpy(std.mem.asBytes(&v), bytes[off..][0..sizes[ci]]);
                            if (!valueEql(v, want)) return false;
                        },
                        else => unreachable,
                    }
                    if (subset & ~((b << 1) -% 1) == 0) return true;
                }
                off += sizes[i];
            }
            return true;
        }

        /// The storage of a declared field's value (unaligned), or null when `canPatch` is
        /// false (not declared, or a shared write-form constant). Reading it is `get`, writing
        /// it is `patchInPlace` (same requirements), without recomputing the field's offset per
        /// access. Valid while the mask and storage stay: patching any field keeps them; a copy
        /// of an inline declaration has its own bytes.
        pub fn fieldPtr(self: *Self, comptime f: Field) ?*align(1) ValueOf(f) {
            if (!self.canPatch(f)) return null;
            const i = @backingInt(f);
            const off = offsetOf(self.mask, i);
            const dst: []u8 = switch (self.store) {
                .inline_bytes => |*small| small.bytes[0..small.len],
                .packed_bytes => |heap_bytes| @constCast(heap_bytes),
                .dense => unreachable,
            };
            return @ptrCast(dst[off..][0..sizes[i]]);
        }

        /// `patchInPlace` would succeed: the field is declared and the bytes are runtime
        /// storage (not a shared write-form constant).
        pub fn canPatch(self: *const Self, comptime f: Field) bool {
            return self.has(f) and self.store != .dense;
        }

        /// Overwrite one declared field's value in its storage: the mask, the length and every
        /// other field stay; nothing is allocated. Requires `canPatch` and that the caller owns
        /// the bytes exclusively (copies of a heap-backed declaration share its region, and
        /// regions handed out by a cache must never be patched).
        pub fn patchInPlace(self: *Self, comptime f: Field, value: ValueOf(f)) void {
            std.debug.assert(self.canPatch(f));
            const i = @backingInt(f);
            const off = offsetOf(self.mask, i);
            const dst: []u8 = switch (self.store) {
                .inline_bytes => |*small| small.bytes[0..small.len],
                .packed_bytes => |heap_bytes| @constCast(heap_bytes),
                .dense => unreachable,
            };
            @memcpy(dst[off..][0..sizes[i]], std.mem.asBytes(&value));
        }

        /// Runtime encoding: small declarations stay inline; larger byte regions
        /// are allocated and must be freed with deinit. Dense/empty values do not allocate.
        pub fn encode(allocator: std.mem.Allocator, s: S) std.mem.Allocator.Error!Self {
            var mask: Mask = 0;
            inline for (fields, 0..) |f, i| {
                if (@field(s, f.name) != null) mask |= bit(i);
            }
            if (mask == 0) return .{};
            const n = byteLen(mask);
            var result: Self = .{ .mask = mask, .store = if (n <= inline_capacity)
                .{ .inline_bytes = .{ .bytes = @splat(0), .len = @intCast(n) } }
            else
                .{ .packed_bytes = try allocator.alloc(u8, n) } };
            const bytes: []u8 = switch (result.store) {
                .inline_bytes => |*small| small.bytes[0..small.len],
                .packed_bytes => |heap_bytes| @constCast(heap_bytes),
                .dense => unreachable,
            };
            var off: usize = 0;
            // Write field-by-field (index ascending, matches offsetOf); no bulk struct copy.
            inline for (fields, 0..) |f, i| {
                if (@field(s, f.name)) |v| {
                    @memcpy(bytes[off..][0..sizes[i]], std.mem.asBytes(&v));
                    off += sizes[i];
                }
            }
            std.debug.assert(off == bytes.len);
            return result;
        }

        /// Borrowed fixed-address storage; the owner must keep it alive until
        /// all declaration copies are retired. Preview layers use this to make
        /// their commit allocation-free. deinit never frees dense storage.
        pub fn fromBorrowed(s: *const S) Self {
            var mask: Mask = 0;
            inline for (fields, 0..) |f, i| {
                if (@field(s.*, f.name) != null) mask |= bit(i);
            }
            return .{ .mask = mask, .store = .{ .dense = s } };
        }

        /// Points to write-form constant (compile-time literal, one global); no allocation.
        pub fn fromConst(comptime s: *const S) Self {
            const mask = comptime blk: {
                var m: Mask = 0;
                for (fields, 0..) |f, i| {
                    if (@field(s.*, f.name) != null) m |= bit(i);
                }
                break :blk m;
            };
            if (mask == 0) return .{};
            return .{ .mask = mask, .store = .{ .dense = s } };
        }

        pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
            switch (self.store) {
                .packed_bytes => |b| if (b.len != 0) allocator.free(b),
                .dense, .inline_bytes => {},
            }
        }

        /// Restore to write-form (undeclared fields are null).
        pub fn decode(self: Self) S {
            if (self.store == .dense) return self.store.dense.*;
            var out: S = .{};
            const bytes = self.packedBytes();
            var off: usize = 0;
            // Encoding stores present fields in declaration order. Walk that
            // stream once instead of recomputing each field's prefix offset.
            inline for (fields, 0..) |f, i| {
                if (self.mask & bit(i) != 0) {
                    var v: @typeInfo(f.type).optional.child = undefined;
                    @memcpy(std.mem.asBytes(&v), bytes[off..][0..sizes[i]]);
                    @field(out, f.name) = v;
                    off += sizes[i];
                } else @field(out, f.name) = null;
            }
            std.debug.assert(off == bytes.len);
            return out;
        }

        /// Overlay declared values on an existing style. A cascade does not
        /// need a dense temporary (and its undeclared null fields) per layer.
        /// Values are copied before the declaration's storage can be retired.
        pub fn mergeInto(self: *const Self, out: *S) void {
            if (self.store == .dense) {
                inline for (fields) |f| {
                    if (@field(self.store.dense.*, f.name)) |v| @field(out.*, f.name) = v;
                }
                return;
            }
            const bytes = self.packedBytes();
            var off: usize = 0;
            inline for (fields, 0..) |f, i| {
                if (self.mask & bit(i) != 0) {
                    var v: @typeInfo(f.type).optional.child = undefined;
                    @memcpy(std.mem.asBytes(&v), bytes[off..][0..sizes[i]]);
                    @field(out.*, f.name) = v;
                    off += sizes[i];
                }
            }
            std.debug.assert(off == bytes.len);
        }

        /// Compare with a write-form style without allocating or repeatedly
        /// scanning packed prefixes. Null remains distinct from a declared
        /// default value; field equality keeps the normal NaN/handle semantics.
        pub fn eqlStyle(self: Self, s: S) bool {
            if (self.store == .dense) return valueEql(self.store.dense.*, s);
            const bytes = self.packedBytes();
            var off: usize = 0;
            inline for (fields, 0..) |f, i| {
                const present = self.mask & bit(i) != 0;
                if ((@field(s, f.name) != null) != present) return false;
                if (present) {
                    var v: @typeInfo(f.type).optional.child = undefined;
                    @memcpy(std.mem.asBytes(&v), bytes[off..][0..sizes[i]]);
                    if (!valueEql(v, @field(s, f.name).?)) return false;
                    off += sizes[i];
                }
            }
            std.debug.assert(off == bytes.len);
            return true;
        }

        /// Equality: same storage -> equal; different bitsets -> not equal; else compare
        /// each declared field value. Bias toward "not equal": false negative only costs
        /// one extra downstream calculation; false positive misses updates.
        pub fn eql(a: Self, b: Self) bool {
            if (a.mask != b.mask) return false;
            if (a.mask == 0) return true;
            if (sameStore(a.store, b.store)) return true;
            inline for (fields, 0..) |_, i| {
                if (a.mask & bit(i) != 0) {
                    const f: Field = @fromBackingInt(@intCast(i));
                    if (!valueEql(a.get(f).?, b.get(f).?)) return false;
                }
            }
            return true;
        }

        /// Pointer shortcut only for compile-time constants (never freed). Not for packed
        /// byte regions: after free, address reused for same-length declaration, address
        /// check causes false-equal and missed updates.
        fn sameStore(x: Store, y: Store) bool {
            return x == .dense and y == .dense and x.dense == y.dense;
        }

        pub fn format(self: Self, w: *std.Io.Writer) std.Io.Writer.Error!void {
            try w.writeAll(@typeName(S) ++ "{");
            var first = true;
            inline for (fields, 0..) |f, i| {
                if (self.mask & bit(i) != 0) {
                    try w.writeAll(if (first) " ." else ", .");
                    first = false;
                    try w.writeAll(f.name);
                    try w.print(" = {any}", .{self.get(@as(Field, @fromBackingInt(@intCast(i)))).?});
                }
            }
            try w.writeAll(if (first) "}" else " }");
        }
    };
}

/// Value equality (same semantics as style runtime: float exact comparison, NaN ==
/// NaN).
pub fn valueEql(a: anytype, b: @TypeOf(a)) bool {
    const T = @TypeOf(a);
    return switch (@typeInfo(T)) {
        .float => a == b or (std.math.isNan(a) and std.math.isNan(b)),
        .optional => if (a) |av| (if (b) |bv| valueEql(av, bv) else false) else b == null,
        .@"struct" => blk: {
            inline for (@import("zenit_reflection").fields(T)) |f| {
                if (!valueEql(@field(a, f.name), @field(b, f.name))) break :blk false;
            }
            break :blk true;
        },
        .array => blk: {
            for (a, b) |av, bv| if (!valueEql(av, bv)) break :blk false;
            break :blk true;
        },
        .vector => |v| blk: {
            inline for (0..v.len) |i| if (!valueEql(a[i], b[i])) break :blk false;
            break :blk true;
        },
        // Address comparison makes "identical content" unequal and "address reuse" equal -
        // disallowed in style values. Exception: explicitly declared handles (see
        // isStyleHandle) where identity is address itself, so address comparison is correct.
        .pointer => |ptr| if (comptime isStyleHandle(ptr)) a == b else @compileError("valueEql: " ++ @typeName(T) ++ " is a pointer; style values must be plain data"),
        .@"union" => |u| blk: {
            if (u.tag_type == null) @compileError("StyleDecl: untagged union " ++ @typeName(T));
            const tag = std.meta.activeTag(a);
            if (tag != std.meta.activeTag(b)) break :blk false;
            inline for (u.field_names) |name| {
                if (tag == @field(std.meta.Tag(T), name)) break :blk valueEql(@field(a, name), @field(b, name));
            }
            unreachable;
        },
        else => a == b,
    };
}

/// Style handle: pointer to runtime-owned stable-address table (e.g.
/// GlassGroupShapes); style values carry only the pointer. Identity = address
/// (equality by address; encoding copies pointer bytes only). Pointee type must
/// declare `pub const style_handle = true`.
fn isStyleHandle(comptime ptr: std.builtin.Type.Pointer) bool {
    if (ptr.size != .one) return false;
    const C = ptr.child;
    return @typeInfo(C) == .@"struct" and @hasDecl(C, "style_handle") and C.style_handle;
}

/// Compile-time check field values are fixed-size: no pointers/slices (encoding
/// copies bytes; pointers break equality and lifetime semantics). Exception:
/// explicitly declared style handles (see isStyleHandle).
fn assertFixedSize(comptime T: type, comptime name: []const u8) void {
    switch (@typeInfo(T)) {
        .pointer => |ptr| if (!isStyleHandle(ptr)) @compileError("StyleDecl: field " ++ name ++ " holds a pointer (" ++ @typeName(T) ++ "); style values must be fixed-size data"),
        .optional => |o| assertFixedSize(o.child, name),
        .array => |a| assertFixedSize(a.child, name),
        .vector => |v| assertFixedSize(v.child, name),
        .@"struct" => |s| for (s.field_types) |FieldType| assertFixedSize(FieldType, name),
        .@"union" => |u| for (u.field_types) |FieldType| assertFixedSize(FieldType, name),
        else => {},
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;
const types = @import("core/types.zig");
const BoxStyle = types.BoxStyle;
const BoxDecl = StyleDecl(BoxStyle);

test "StyleDecl: cascade overlays preserve lower fields and own declared values" {
    const styles = [_]BoxStyle{
        .{},
        .{ .translate_x = 0, .translate_y = -12, .opacity = 0 },
        .{ .width = .{ .px = 96 }, .background = types.Color.rgb(4, 5, 6), .shadow = .{ .blur = 16, .offset_y = 4 } },
        .{ .translate_x = std.math.nan(f32), .border_width = 0, .border_color = types.Color.TRANSPARENT },
        .{ .height = .{ .percent = 50 }, .corner_radius = 12, .text_color = types.Color.rgb(0, 0, 0) },
    };
    inline for (styles) |lower| {
        inline for (styles) |upper| {
            const expected = lower.merge(upper);
            const declaration = try BoxDecl.encode(testing.allocator, upper);
            var actual = lower;
            declaration.mergeInto(&actual);
            declaration.deinit(testing.allocator);
            // The result remains valid after the packed layer is retired.
            try testing.expect(valueEql(expected, actual));

            const borrowed = BoxDecl.fromBorrowed(&upper);
            actual = lower;
            borrowed.mergeInto(&actual);
            try testing.expect(valueEql(expected, actual));
        }
    }
}

test "StyleDecl: packed cursor preserves omitted defaults and mixed-size values" {
    const S = struct {
        enabled: ?bool = true,
        weight: ?u64 = 99,
        opacity: ?f32 = 1,
        offset: ?i16 = null,
    };
    const Decl = StyleDecl(S);
    const cases = [_]S{
        .{ .enabled = null, .weight = null, .opacity = null },
        .{ .enabled = false, .weight = 0x1234_5678_90ab_cdef, .opacity = null, .offset = -23 },
        .{ .enabled = null, .weight = null, .opacity = std.math.nan(f32), .offset = 32767 },
    };
    for (cases) |s| {
        const d = try Decl.encode(testing.allocator, s);
        defer d.deinit(testing.allocator);
        const dense = Decl.fromBorrowed(&s);
        try testing.expect(valueEql(s, d.decode()));
        try testing.expect(d.eqlStyle(s) and dense.eqlStyle(s));
        var changed = s;
        changed.enabled = if (s.enabled) |v| !v else false;
        try testing.expect(!d.eqlStyle(changed) and !dense.eqlStyle(changed));
    }
}

test "StyleDecl: 只存声明了的字段；get / decode 还原；空声明不分配" {
    const s: BoxStyle = .{ .background = types.Color.rgb(255, 0, 0), .gap = 8, .padding = types.Padding.all(4) };
    const d = try BoxDecl.encode(testing.allocator, s);
    defer d.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 3), d.count());
    try testing.expect(d.packedBytes().len < 64);
    try testing.expect(valueEql(d.get(.background).?, types.Color.rgb(255, 0, 0)));
    try testing.expectEqual(@as(?f32, 8), d.get(.gap));
    try testing.expect(d.get(.opacity) == null);
    try testing.expect(valueEql(d.decode(), s));
    const e = try BoxDecl.encode(testing.allocator, .{});
    try testing.expect(e.isEmpty() and e.packedBytes().len == 0);
}

test "StyleDecl: 往返性质——76 个字段逐个单独声明、以及随机子集，编码再解码与原值相等" {
    const fields = @import("zenit_reflection").fields(BoxStyle);
    // Sample with all fields valued: taken from default construction (zero/default for
    // each field type).
    var full: BoxStyle = .{};
    inline for (fields) |f| {
        const V = @typeInfo(f.type).optional.child;
        @field(full, f.name) = sample(V);
    }
    // Each field declared separately.
    inline for (fields) |f| {
        var one: BoxStyle = .{};
        @field(one, f.name) = @field(full, f.name);
        const d = try BoxDecl.encode(testing.allocator, one);
        defer d.deinit(testing.allocator);
        try testing.expectEqual(@as(usize, 1), d.count());
        try testing.expect(valueEql(d.decode(), one));
    }
    // Random subset.
    var prng = std.Random.DefaultPrng.init(0x5717_e5ec);
    const r = prng.random();
    for (0..200) |_| {
        var sub: BoxStyle = .{};
        inline for (fields) |f| {
            if (r.boolean()) @field(sub, f.name) = @field(full, f.name);
        }
        const d = try BoxDecl.encode(testing.allocator, sub);
        defer d.deinit(testing.allocator);
        try testing.expect(valueEql(d.decode(), sub));
        try testing.expect(d.eqlStyle(sub));
        try testing.expectEqual(valueEql(sub, full), d.eqlStyle(full));
        try testing.expectEqual(valueEql(sub, BoxStyle{}), d.eqlStyle(.{}));
        // Each field read back separately.
        inline for (fields, 0..) |f, i| {
            try testing.expect(valueEql(d.get(@as(BoxDecl.Field, @fromBackingInt(@intCast(i)))), @field(sub, f.name)));
        }
    }
}

/// One non-default sample for each field type (round-trip test catches byte
/// alignment errors).
fn sample(comptime T: type) T {
    var v: T = undefined;
    const bytes = std.mem.asBytes(&v);
    for (bytes, 0..) |*b, i| b.* = @truncate(i *% 31 +% 7);
    return switch (@typeInfo(T)) {
        // Byte-filled enum/bool/union may not be legal values: use defaults.
        .@"enum" => @fromBackingInt(@intCast(@import("zenit_reflection").fields(T)[@import("zenit_reflection").fields(T).len - 1].value)),
        .bool => true,
        .float => 3.25,
        .int => 7,
        .@"struct", .@"union" => defaultOf(T),
        else => v,
    };
}

fn defaultOf(comptime T: type) T {
    if (@typeInfo(T) == .@"struct") {
        var out: T = undefined;
        inline for (@import("zenit_reflection").fields(T)) |f| {
            @field(out, f.name) = if (f.defaultValue()) |d| d else sample(f.type);
        }
        return out;
    }
    // Union: take first field.
    const f0 = @import("zenit_reflection").fields(T)[0];
    return @unionInit(T, f0.name, sample(f0.type));
}

test "StyleDecl: 判等——位集不同即不等；共同字段逐个比较值；dense 与 packed 可以互比" {
    const a = try BoxDecl.encode(testing.allocator, .{ .background = types.Color.rgb(1, 2, 3), .opacity = 0.5 });
    defer a.deinit(testing.allocator);
    const b = try BoxDecl.encode(testing.allocator, .{ .background = types.Color.rgb(1, 2, 3), .opacity = 0.5 });
    defer b.deinit(testing.allocator);
    const c = try BoxDecl.encode(testing.allocator, .{ .background = types.Color.rgb(1, 2, 4), .opacity = 0.5 });
    defer c.deinit(testing.allocator);
    const d = try BoxDecl.encode(testing.allocator, .{ .background = types.Color.rgb(1, 2, 3) });
    defer d.deinit(testing.allocator);
    try testing.expect(a.eql(b));
    try testing.expect(!a.eql(c));
    try testing.expect(!a.eql(d)); // Declare one fewer field: not equal (undeclaring is a change).
    const lit = comptime BoxStyle{ .background = types.Color.rgb(1, 2, 3), .opacity = 0.5 };
    const k = BoxDecl.fromConst(&lit);
    try testing.expect(k.eql(a) and a.eql(k));
    try testing.expect(k.eql(BoxDecl.fromConst(&lit)));
    try testing.expect(BoxDecl.eql(.{}, .{}));
    try testing.expect(a.eqlStyle(k.decode()) and k.eqlStyle(a.decode()));
    try testing.expect(!a.eqlStyle(c.decode()) and !k.eqlStyle(c.decode()));
    try testing.expect(!a.eqlStyle(d.decode()));
}

test "StyleDecl: Button 的三份覆盖——不传覆盖时为空，传一个字段时只占这个字段" {
    const empty = try BoxDecl.encode(testing.allocator, .{});
    try testing.expectEqual(@as(usize, 0), empty.packedBytes().len);
    const one = try BoxDecl.encode(testing.allocator, .{ .background = types.Color.rgb(9, 9, 9) });
    defer one.deinit(testing.allocator);
    try testing.expectEqual(@sizeOf(types.Color), one.packedBytes().len);
    try testing.expect(@sizeOf(BoxDecl) <= 48);
}

test "StyleDecl: small values survive owner copies without allocation; larger values retain OOM contract" {
    const S = struct { a: ?usize = null, b: ?usize = null, extra: ?u8 = null };
    const Decl = StyleDecl(S);
    var failing = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 0 });
    const no_alloc = failing.allocator();
    const s: S = .{ .a = @truncate(@as(u64, 0x0123_4567_89ab_cdef)), .b = @truncate(@as(u64, 0xfedc_ba98_7654_3210)) };
    var original = try Decl.encode(no_alloc, s);
    const copy = original;
    original.deinit(no_alloc);
    original = .{};
    try testing.expect(valueEql(s, copy.decode()));
    try testing.expect(copy.eqlStyle(s));
    try testing.expectEqual(s.b, copy.get(.b));
    copy.deinit(no_alloc);
    const HeapOnly = struct {
        mask: u128,
        store: union(enum) { packed_bytes: []const u8, dense: *const S },
    };
    try testing.expectEqual(@sizeOf(HeapOnly), @sizeOf(Decl));

    const large: S = .{ .a = s.a, .b = s.b, .extra = 7 };
    try testing.expectError(error.OutOfMemory, Decl.encode(no_alloc, large));
    const heap = try Decl.encode(testing.allocator, large);
    defer heap.deinit(testing.allocator);
    try testing.expect(valueEql(large, heap.decode()));
    try testing.expect(heap.eqlStyle(large));
    try testing.expect(!heap.eql(copy));
}

test "StyleDecl: patchInPlace rewrites one declared value in inline and heap storage; eqlFields compares a subset" {
    const small: BoxStyle = .{ .translate_x = 1, .translate_y = 2 };
    const large: BoxStyle = .{ .border_width = 0, .border_color = types.Color.TRANSPARENT, .shadow = .{ .blur = 16, .offset_y = 4 }, .translate_x = 1, .translate_y = 2 };
    inline for (.{ small, large }) |s| {
        var d = try BoxDecl.encode(testing.allocator, s);
        defer d.deinit(testing.allocator);
        const mask = d.mask;
        try testing.expectEqual(mask, BoxDecl.maskOf(&s));
        try testing.expect(d.canPatch(.translate_y) and !d.canPatch(.opacity));
        d.patchInPlace(.translate_y, -7.5);
        var want = s;
        want.translate_y = -7.5;
        try testing.expectEqual(mask, d.mask);
        try testing.expect(valueEql(d.decode(), want));
        try testing.expect(d.eqlStyle(want));
        // subset: everything but the translates still equals the original
        const rest = mask & ~(BoxDecl.fieldBit(.translate_x) | BoxDecl.fieldBit(.translate_y));
        try testing.expect(d.eqlFields(&s, rest));
        try testing.expect(!d.eqlFields(&s, mask));
        try testing.expect(d.eqlFields(&want, mask));
        const dense = BoxDecl.fromBorrowed(&want);
        try testing.expect(!dense.canPatch(.translate_y));
        try testing.expect(dense.eqlFields(&want, mask) and !dense.eqlFields(&s, mask));
    }
}

/// The former eqlFields: every field of S in index order (reference for the test below).
fn eqlFieldsReference(d: *const BoxDecl, s: *const BoxStyle, subset: BoxDecl.Mask) bool {
    inline for (@import("zenit_reflection").fields(BoxStyle), 0..) |f, i| {
        if (subset & (@as(BoxDecl.Mask, 1) << i) != 0) {
            const want = @field(s.*, f.name) orelse return false;
            if (!valueEql(d.get(@as(BoxDecl.Field, @fromBackingInt(i))).?, want)) return false;
        }
    }
    return true;
}

test "StyleDecl: eqlFields 只走声明过的字段，任意子集与逐字段参考实现结论一致；fieldPtr 读写同 get / patchInPlace" {
    const full: BoxStyle = .{
        .width = .{ .px = 10 },
        .padding = .{ .left = 3 },
        .flex_shrink = 0,
        .z_index = 2,
        .corner_radius = 12,
        .background = types.Color.hex(0x123456),
        .opacity = 0.5,
        .translate_x = 1,
        .translate_y = 2,
        .border_width = 0,
        .border_color = types.Color.TRANSPARENT,
        .shadow = .{ .blur = 16, .offset_y = 4 },
        .text_color = types.Color.hex(0x654321),
        .icon_color = types.Color.hex(0x111111),
    };
    var d = try BoxDecl.encode(testing.allocator, full);
    defer d.deinit(testing.allocator);
    const mask = d.mask;
    try testing.expectEqual(@as(usize, 14), @popCount(mask));
    // probes: equal, one declared field changed (a few positions), one declared field missing
    // (every position)
    var probes: std.ArrayList(BoxStyle) = .empty;
    defer probes.deinit(testing.allocator);
    try probes.append(testing.allocator, full);
    inline for (@import("zenit_reflection").fields(BoxStyle)) |f| {
        if (@field(full, f.name) != null) {
            var missing = full;
            @field(missing, f.name) = null;
            try probes.append(testing.allocator, missing);
        }
    }
    inline for (.{
        BoxStyle{ .width = .{ .px = 11 } },
        BoxStyle{ .padding = .{ .left = 4 } },
        BoxStyle{ .flex_shrink = 1 },
        BoxStyle{ .z_index = 3 },
        BoxStyle{ .background = types.Color.hex(0x123457) },
        BoxStyle{ .translate_x = 1.5 },
        BoxStyle{ .translate_y = 2.5 },
        BoxStyle{ .border_color = types.Color.hex(0x000001) },
        BoxStyle{ .shadow = .{ .blur = 15, .offset_y = 4 } },
        BoxStyle{ .icon_color = types.Color.hex(0x111112) },
    }) |delta| try probes.append(testing.allocator, full.merge(delta));
    var prng = std.Random.DefaultPrng.init(0x5eed);
    const r = prng.random();
    for (0..2000) |step| {
        var subset: BoxDecl.Mask = 0;
        var m = mask;
        while (m != 0) : (m &= m - 1) {
            if (r.boolean()) subset |= @as(BoxDecl.Mask, 1) << @intCast(@ctz(m));
        }
        if (step == 0) subset = mask;
        if (step == 1) subset = 0;
        for (probes.items) |*p| try testing.expectEqual(eqlFieldsReference(&d, p, subset), d.eqlFields(p, subset));
    }
    // fieldPtr
    try testing.expect(d.fieldPtr(.margin) == null);
    const px = d.fieldPtr(.translate_x).?;
    try testing.expectEqual(d.get(.translate_x).?, px.*);
    px.* = -4.5;
    try testing.expectEqual(@as(f32, -4.5), d.get(.translate_x).?);
    try testing.expectEqual(mask, d.mask);
    var want = full;
    want.translate_x = -4.5;
    try testing.expect(d.eqlStyle(want));
    var inl = try BoxDecl.encode(testing.allocator, .{ .translate_x = 1, .translate_y = 2 });
    defer inl.deinit(testing.allocator);
    inl.fieldPtr(.translate_y).?.* = 9;
    try testing.expect(inl.eqlStyle(.{ .translate_x = 1, .translate_y = 9 }));
    var dense = BoxDecl.fromBorrowed(&full);
    try testing.expect(dense.fieldPtr(.translate_x) == null);
}
