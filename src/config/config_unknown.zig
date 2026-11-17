//! Opaque round-trip preservation of config.toml content this version does not
//! understand (keys or sections written by a newer or older ZeroWork).
//!
//! Unknown content is never interpreted: it is kept as validated single-line
//! text and written back verbatim in the section it came from. Every preserved
//! line is checked again before it is written so that it cannot open a new
//! section or smuggle in an extra assignment. Bounded by `max_*` below; content
//! over a limit, or text that cannot be re-emitted safely, is skipped without
//! being preserved. Warnings name keys and sections only, never values.
const std = @import("std");
const log = std.log.scoped(.config);

/// Preserved items (unknown keys, unknown section headers, lines inside them).
pub const max_entries = 256;
/// One preserved line (`key = value`, a section header or a comment line).
pub const max_line_bytes = 4096;
/// Sum of all preserved line bytes.
pub const max_total_bytes = 64 * 1024;
/// Warnings emitted per parse before a single "further entries" summary.
const max_logged = 32;

/// Which known table an unknown key belongs to.
pub const Table = enum { section, provider, model, preference };
pub const Kind = enum {
    /// `key = value` inside a known section or known array-table entry.
    key,
    /// Header of an unknown section (`[name]` or `[[name]]`).
    header,
    /// Assignment or full-line comment inside the preceding unknown header.
    line,
};

pub const Entry = struct {
    kind: Kind,
    table: Table = .section,
    /// `.key` in `.section`: the known section name ("" is the top level).
    /// `.header`/`.line`: the known section the unknown block followed.
    section: []const u8 = "",
    /// `.provider`/`.model`: provider id. `.preference`: plugin_id.
    owner: []const u8 = "",
    /// `.model`: model name. `.preference`: preference key.
    owner_b: []const u8 = "",
    text: []const u8,
    /// Parse-time positions used only to resolve `owner`/`owner_b`.
    index: usize = 0,
    sub_index: usize = 0,
};

pub const Unknown = struct {
    entries: []const Entry = &.{},
    /// Unknown keys and unknown sections that were skipped with a warning.
    skipped: u32 = 0,
    /// Skipped items that could not be preserved (limits, unsafe text, no allocator).
    dropped: u32 = 0,

    pub fn clone(self: Unknown, allocator: std.mem.Allocator) !Unknown {
        const entries = try allocator.alloc(Entry, self.entries.len);
        for (entries, self.entries) |*destination, source| {
            destination.* = source;
            destination.section = try allocator.dupe(u8, source.section);
            destination.owner = try allocator.dupe(u8, source.owner);
            destination.owner_b = try allocator.dupe(u8, source.owner_b);
            destination.text = try allocator.dupe(u8, source.text);
        }
        return .{ .entries = entries, .skipped = self.skipped, .dropped = self.dropped };
    }

    pub fn validate(self: Unknown) error{InvalidValue}!void {
        if (self.entries.len > max_entries) return error.InvalidValue;
        var total: usize = 0;
        for (self.entries) |entry| {
            if (!validEntry(entry)) return error.InvalidValue;
            total += entry.text.len;
        }
        if (total > max_total_bytes) return error.InvalidValue;
    }

    /// Unknown keys owned by one known section or array-table entry. An empty
    /// owner never matches, so entries of an anonymous table are not re-emitted.
    pub fn writeKeys(self: Unknown, writer: *std.Io.Writer, table: Table, section: []const u8, owner: []const u8, owner_b: []const u8) !usize {
        var count: usize = 0;
        for (self.entries) |entry| {
            if (entry.kind != .key or entry.table != table) continue;
            switch (table) {
                .section => if (!eq(entry.section, section)) continue,
                .provider => if (owner.len == 0 or !eq(entry.owner, owner)) continue,
                .model, .preference => if (owner.len == 0 or !eq(entry.owner, owner) or !eq(entry.owner_b, owner_b)) continue,
            }
            if (!validEntry(entry)) return error.InvalidUnknownEntry;
            try writer.writeAll(entry.text);
            try writer.writeByte('\n');
            count += 1;
        }
        return count;
    }

    /// Unknown sections that followed known section `anchor`, in file order.
    pub fn writeBlocks(self: Unknown, writer: *std.Io.Writer, anchor: []const u8) !void {
        var open = false;
        var written = false;
        for (self.entries) |entry| switch (entry.kind) {
            .key => {},
            .header => {
                open = eq(entry.section, anchor);
                if (!open) continue;
                if (!validEntry(entry)) return error.InvalidUnknownEntry;
                if (written) try writer.writeByte('\n');
                try writer.writeAll(entry.text);
                try writer.writeByte('\n');
                written = true;
            },
            .line => {
                // A line is only ever emitted directly below its own header.
                if (!open or !eq(entry.section, anchor)) continue;
                if (!validEntry(entry)) return error.InvalidUnknownEntry;
                try writer.writeAll(entry.text);
                try writer.writeByte('\n');
            },
        };
        if (written) try writer.writeByte('\n');
    }

    /// Keys of a known section, a separating blank line, then trailing blocks.
    pub fn writeTrailer(self: Unknown, writer: *std.Io.Writer, section: []const u8) !void {
        if (try self.writeKeys(writer, .section, section, "", "") != 0) try writer.writeByte('\n');
        try self.writeBlocks(writer, section);
    }
};

/// Placement of an unknown key as seen by the parser.
pub const Placement = union(Table) {
    section: []const u8,
    provider: usize,
    model: struct { provider: usize, model: usize },
    preference: usize,
};

pub const Collector = struct {
    allocator: ?std.mem.Allocator,
    list: std.ArrayList(Entry) = .empty,
    bytes: usize = 0,
    skipped: u32 = 0,
    dropped: u32 = 0,
    logged: u32 = 0,
    /// The current unknown section's header was not preserved; drop its lines.
    block_dropped: bool = false,
    block_anchor: []const u8 = "",

    pub fn key(self: *Collector, placement: Placement, name: []const u8, value: []const u8) error{OutOfMemory}!void {
        self.skipped += 1;
        const where = switch (placement) {
            .section => |section| if (section.len == 0) "<top level>" else section,
            .provider => "ai.providers",
            .model => "ai.providers.models",
            .preference => "plugin_preferences",
        };
        const reason = self.admit(validKey(name) and validValue(value), 3 + name.len + value.len);
        self.warn("ignoring unknown config key \"{s}\" in [{s}] ({s})", .{ displayKey(name), where, reasonText(reason) });
        if (reason != .preserved) return;
        var entry: Entry = .{ .kind = .key, .text = try std.fmt.allocPrint(self.allocator.?, "{s} = {s}", .{ name, value }) };
        switch (placement) {
            .section => |section| entry.section = section,
            .provider => |index| {
                entry.table = .provider;
                entry.index = index;
            },
            .model => |position| {
                entry.table = .model;
                entry.index = position.provider;
                entry.sub_index = position.model;
            },
            .preference => |index| {
                entry.table = .preference;
                entry.index = index;
            },
        }
        try self.push(entry);
    }

    /// `line` is a comment-stripped, trimmed header already rejected as known.
    pub fn beginBlock(self: *Collector, anchor: []const u8, line: []const u8) error{OutOfMemory}!void {
        self.skipped += 1;
        self.block_anchor = anchor;
        const name = headerName(line) orelse "";
        const array = std.mem.startsWith(u8, line, "[[");
        const reason = self.admit(validKey(name), name.len + @as(usize, if (array) 4 else 2));
        self.warn("ignoring unknown config section [{s}] ({s})", .{ displayKey(name), reasonText(reason) });
        self.block_dropped = reason != .preserved;
        if (self.block_dropped) return;
        const text = if (array) try std.fmt.allocPrint(self.allocator.?, "[[{s}]]", .{name}) else try std.fmt.allocPrint(self.allocator.?, "[{s}]", .{name});
        try self.push(.{ .kind = .header, .section = anchor, .text = text });
    }

    pub fn blockLine(self: *Collector, name: []const u8, value: []const u8) error{OutOfMemory}!void {
        if (self.block_dropped) return;
        const reason = self.admit(validKey(name) and validValue(value), 3 + name.len + value.len);
        if (reason != .preserved) {
            self.warn("ignoring key \"{s}\" inside unknown config section ({s})", .{ displayKey(name), reasonText(reason) });
            return;
        }
        const text = try std.fmt.allocPrint(self.allocator.?, "{s} = {s}", .{ name, value });
        try self.push(.{ .kind = .line, .section = self.block_anchor, .text = text });
    }

    pub fn blockComment(self: *Collector, comment: []const u8) error{OutOfMemory}!void {
        if (self.block_dropped) return;
        // Comments are best effort: dropped silently when unsafe or over a limit.
        if (!validComment(comment) or self.allocator == null or self.list.items.len >= max_entries or self.bytes + comment.len > max_total_bytes) return;
        try self.push(.{ .kind = .line, .section = self.block_anchor, .text = try self.allocator.?.dupe(u8, comment) });
    }

    /// Call after the caller has filled `owner`/`owner_b` of array-table
    /// entries from `index`/`sub_index` (an id may follow its unknown keys).
    /// Entries whose table has no id cannot be matched on write and are dropped.
    pub fn finish(self: *Collector) Unknown {
        var kept: usize = 0;
        for (self.list.items) |entry| {
            if (entry.table != .section and (entry.owner.len == 0 or (entry.table != .provider and entry.owner_b.len == 0))) {
                self.dropped += 1;
                self.warn("unknown config key in an array table without an id is not preserved", .{});
                continue;
            }
            self.list.items[kept] = entry;
            kept += 1;
        }
        if (self.logged > max_logged) log.warn("{d} further unknown config entries were not logged", .{self.logged - max_logged});
        return .{ .entries = self.list.items[0..kept], .skipped = self.skipped, .dropped = self.dropped };
    }

    const Reason = enum { preserved, unsafe, limit, no_allocator };

    fn admit(self: *Collector, safe: bool, line_bytes: usize) Reason {
        const reason: Reason = if (!safe) .unsafe else if (line_bytes > max_line_bytes or self.list.items.len >= max_entries or self.bytes + line_bytes > max_total_bytes) .limit else if (self.allocator == null) .no_allocator else .preserved;
        if (reason != .preserved) self.dropped += 1;
        return reason;
    }

    fn push(self: *Collector, entry: Entry) error{OutOfMemory}!void {
        try self.list.append(self.allocator.?, entry);
        self.bytes += entry.text.len;
    }

    fn warn(self: *Collector, comptime format: []const u8, args: anytype) void {
        self.logged += 1;
        if (self.logged <= max_logged) log.warn(format, args);
    }
};

fn reasonText(reason: Collector.Reason) []const u8 {
    return switch (reason) {
        .preserved => "preserved",
        .unsafe => "not preserved: unsupported syntax",
        .limit => "not preserved: size limit",
        .no_allocator => "not preserved",
    };
}

/// Only names that pass validation are echoed; anything else may be data.
fn displayKey(name: []const u8) []const u8 {
    return if (validKey(name)) name else "<invalid name>";
}

/// `[name]` / `[[name]]` with optional spaces inside the brackets.
pub fn headerName(line: []const u8) ?[]const u8 {
    const array = std.mem.startsWith(u8, line, "[[") and std.mem.endsWith(u8, line, "]]");
    if (!array and (line.len < 2 or line[0] != '[' or line[line.len - 1] != ']')) return null;
    const inner = if (array) line[2 .. line.len - 2] else line[1 .. line.len - 1];
    const name = std.mem.trim(u8, inner, " \t");
    return if (validKey(name)) name else null;
}

/// Bare TOML keys, optionally dotted: [A-Za-z0-9_-] segments joined by '.'.
pub fn validKey(name: []const u8) bool {
    if (name.len == 0 or name.len > 128 or name[0] == '.' or name[name.len - 1] == '.') return false;
    var previous_dot = false;
    for (name) |byte| {
        const dot = byte == '.';
        if (dot and previous_dot) return false;
        if (!dot and !std.ascii.isAlphanumeric(byte) and byte != '_' and byte != '-') return false;
        previous_dot = dot;
    }
    return true;
}

/// A single-line scalar, array or inline table as tokenized by config.zig:
/// UTF-8 without control characters, closed quotes and escapes, balanced
/// brackets, and no unquoted `#` or `;` (which would start a comment or a
/// second assignment when the line is read back).
pub fn validValue(value: []const u8) bool {
    if (value.len == 0 or value.len > max_line_bytes or !std.unicode.utf8ValidateSlice(value)) return false;
    var quoted = false;
    var escaped = false;
    var depth: usize = 0;
    for (value) |byte| {
        if ((byte < 0x20 and byte != '\t') or byte == 0x7f) return false;
        if (quoted) {
            if (escaped) {
                escaped = false;
            } else if (byte == '\\') {
                escaped = true;
            } else if (byte == '"') quoted = false;
            continue;
        }
        switch (byte) {
            '"' => quoted = true,
            '#', ';' => return false,
            '[', '{' => depth += 1,
            ']', '}' => {
                if (depth == 0) return false;
                depth -= 1;
            },
            else => {},
        }
    }
    return !quoted and !escaped and depth == 0;
}

pub fn validComment(text: []const u8) bool {
    if (text.len == 0 or text[0] != '#' or text.len > max_line_bytes or !std.unicode.utf8ValidateSlice(text)) return false;
    for (text) |byte| if ((byte < 0x20 and byte != '\t') or byte == 0x7f) return false;
    return true;
}

fn validAssignment(text: []const u8) bool {
    const separator = std.mem.indexOf(u8, text, " = ") orelse return false;
    return validKey(text[0..separator]) and validValue(text[separator + 3 ..]);
}

pub fn validEntry(entry: Entry) bool {
    if (entry.text.len == 0 or entry.text.len > max_line_bytes) return false;
    if (entry.kind == .key or entry.kind == .header) {
        if (entry.section.len != 0 and !validKey(entry.section)) return false;
    }
    return switch (entry.kind) {
        .key => validAssignment(entry.text),
        .header => headerName(entry.text) != null and std.mem.indexOfAny(u8, entry.text, " \t") == null,
        .line => validAssignment(entry.text) or validComment(entry.text),
    };
}

fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
