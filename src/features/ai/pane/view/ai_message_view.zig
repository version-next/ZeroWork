//! AI message Markdown (native W.Markdown / W.CodeBlock at the chat scale), streaming retention and text selection.
const ui = @import("ui");
const IdSpace = @import("../../shared/view/ai_id_space.zig").IdSpace;
const std = @import("std");
const S = @import("ai_assistant_styles.zig");
pub fn mount(cx: *ui.Cx, scope: *ui.Scope, value: []const u8) !*ui.Node {
    return mountWithWidth(cx, scope, value, 540);
}
pub fn mountWithWidth(cx: *ui.Cx, scope: *ui.Scope, value: []const u8, width: f32) !*ui.Node {
    return mountWithImages(cx, scope, value, width, null);
}
pub fn mountWithImages(cx: *ui.Cx, scope: *ui.Scope, value: []const u8, width: f32, images: ?@import("../../attachments/view/ai_transcript_images.zig").Context) !*ui.Node {
    return mountContent(cx, scope, value, width, images, true, null);
}
fn mountContent(cx: *ui.Cx, scope: *ui.Scope, value: []const u8, width: f32, images: ?@import("../../attachments/view/ai_transcript_images.zig").Context, selection: bool, retained_code: ?*?*CodeState) !*ui.Node {
    const root = try ui.box(cx, S.assistantMessage(), .{});
    var lines: std.ArrayList([]const u8) = .empty;
    defer lines.deinit(cx.allocator);
    var iterator = std.mem.splitScalar(u8, value, '\n');
    while (iterator.next()) |line| try lines.append(cx.allocator, line);
    var start: usize = 0;
    var i: usize = 0;
    while (i < lines.items.len) : (i += 1) {
        const trimmed = std.mem.trim(u8, lines.items[i], " \t\r");
        if (std.mem.startsWith(u8, trimmed, "```") or std.mem.startsWith(u8, trimmed, "~~~")) {
            try appendMarkdown(cx, scope, root, lines.items[start..i]);
            var fence_len: usize = 0;
            while (fence_len < trimmed.len and trimmed[fence_len] == trimmed[0]) : (fence_len += 1) {}
            var end = i + 1;
            while (end < lines.items.len) : (end += 1) {
                const closing = std.mem.trim(u8, lines.items[end], " \t\r");
                var count: usize = 0;
                while (count < closing.len and closing[count] == trimmed[0]) : (count += 1) {}
                if (count >= fence_len and std.mem.trim(u8, closing[count..], " \t\r").len == 0) break;
            }
            const code = try std.mem.join(cx.allocator, "\n", lines.items[i + 1 .. end]);
            defer cx.allocator.free(code);
            const source = if (end < lines.items.len and end > i + 1) try std.mem.concat(cx.allocator, u8, &.{ code, "\n" }) else try cx.allocator.dupe(u8, code);
            defer cx.allocator.free(source);
            const code_state = try appendCode(cx, scope, root, code, source, trimmed[fence_len..]);
            if (retained_code) |slot| slot.* = code_state;
            i = end;
            start = @min(end + 1, lines.items.len);
            continue;
        }
        if (images) |context| if (@import("../../attachments/view/ai_transcript_images.zig").reference(lines.items[i])) |first| {
            try appendMarkdown(cx, scope, root, lines.items[start..i]);
            var remaining = lines.items[i];
            var ref = first;
            while (true) {
                if (ref.start != 0) try appendMarkdown(cx, scope, root, &.{remaining[0..ref.start]});
                try root.appendChild(cx.allocator, try @import("../../attachments/view/ai_transcript_images.zig").mount(cx, scope, context, ref, width));
                remaining = remaining[ref.end..];
                ref = @import("../../attachments/view/ai_transcript_images.zig").reference(remaining) orelse break;
            }
            if (remaining.len > 0) try appendMarkdown(cx, scope, root, &.{remaining});
            start = i + 1;
            continue;
        };
    }
    try appendMarkdown(cx, scope, root, lines.items[start..]);
    if (selection) try @import("ai_text_selection.zig").attach(cx, scope, root);
    return root;
}
pub fn mountCode(cx: *ui.Cx, scope: *ui.Scope, code: []const u8, language: []const u8) !*ui.Node {
    const root = try ui.box(cx, S.assistantMessage(), .{});
    _ = try appendCode(cx, scope, root, code, code, language);
    try @import("ai_text_selection.zig").attach(cx, scope, root);
    return root;
}
pub fn languageLabel(info: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, info, " \t\r");
    const token = trimmed[0 .. std.mem.indexOfAny(u8, trimmed, " \t") orelse trimmed.len];
    if (token.len == 0) return "代码";
    const aliases = .{
        .{ "yaml", "YAML" },             .{ "yml", "YAML" },      .{ "zig", "Zig" },
        .{ "json", "JSON" },             .{ "jsonc", "JSONC" },   .{ "toml", "TOML" },
        .{ "sh", "Shell" },              .{ "shell", "Shell" },   .{ "bash", "Bash" },
        .{ "zsh", "Zsh" },               .{ "python", "Python" }, .{ "py", "Python" },
        .{ "javascript", "JavaScript" }, .{ "js", "JavaScript" }, .{ "typescript", "TypeScript" },
        .{ "ts", "TypeScript" },         .{ "html", "HTML" },     .{ "css", "CSS" },
        .{ "sql", "SQL" },               .{ "rust", "Rust" },     .{ "rs", "Rust" },
        .{ "cpp", "C++" },               .{ "c", "C" },
        .{ "text", "纯文本" },
        .{ "txt", "纯文本" },
    };
    inline for (aliases) |alias| if (std.ascii.eqlIgnoreCase(token, alias[0])) return alias[1];
    return token;
}
fn appendMarkdown(cx: *ui.Cx, scope: *ui.Scope, parent: *ui.Node, lines: []const []const u8) !void {
    if (lines.len == 0) return;
    const joined = try std.mem.join(cx.allocator, "\n", lines);
    defer cx.allocator.free(joined);
    // Native Markdown at the chat scale (headings, `.rules` tables); no post-processing.
    const node = try ui.widgets.Markdown(.{ .text = try scope.createText(joined, .{}), .options = S.markdownOptions(IdSpace.of(scope)) }).mount(scope, cx);
    try parent.appendChild(cx.allocator, node);
}
pub fn tableSeparator(line: []const u8) bool {
    const value = std.mem.trim(u8, line, " \t\r|");
    if (value.len == 0) return false;
    var cells = std.mem.splitScalar(u8, value, '|');
    while (cells.next()) |cell| {
        const rule = std.mem.trim(u8, cell, " \t:");
        if (rule.len < 3) return false;
        for (rule) |byte| if (byte != '-') return false;
    }
    return true;
}

/// A fenced block is the native W.CodeBlock (Pencil Kaf7E A4): the code is a signal, so a
/// streamed fence updates its text in place; copy writes the original source.
const CodeState = struct {
    code: *ui.Signal([]const u8),
    source: *ui.Signal([]const u8),
    language: *ui.Signal([]const u8),
    fn update(self: *CodeState, code: []const u8, source: []const u8) !void {
        if (!std.mem.eql(u8, self.code.peek(), code)) self.code.set(code);
        if (!std.mem.eql(u8, self.source.peek(), source)) self.source.set(source);
    }
};
fn appendCode(cx: *ui.Cx, scope: *ui.Scope, parent: *ui.Node, code: []const u8, source: []const u8, language: []const u8) !*CodeState {
    const space = IdSpace.of(scope);
    const state = try scope.createState(CodeState, .{ .code = try scope.createText(code, .{}), .source = try scope.createText(source, .{}), .language = try scope.createText(language, .{}) });
    const copy_text = try scope.derive(?[]const u8, .{ .source = state.source }, struct {
        fn f(c: anytype) ?[]const u8 {
            return c.source.get();
        }
    }.f);
    const block = try ui.widgets.CodeBlock(.{
        .code = state.code,
        .copy_text = copy_text,
        .label = languageLabel(language),
        .options = S.markdownOptions(space),
        .labels = .{ .wrap = "自动换行", .unwrap = "取消自动换行", .copy = "复制代码", .copied = "已复制" },
        .test_ids = .{ .block = space.id("ai.message.code"), .header = space.id("ai.message.code.header"), .label = space.id("ai.message.code.language"), .wrap = space.id("ai.message.code.wrap"), .copy = space.id("ai.message.code.copy"), .body = space.id("ai.message.code.scroll"), .text = space.id("ai.message.code.text") },
    }).mount(scope, cx);
    try parent.appendChild(cx.allocator, block);
    return state;
}

// Zenit's Markdown emitter skips empty code lines. Keep a visual blank line
// in the display projection; the conversation and copy source remain original.
pub fn preserveCodeLines(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    var lines = std.mem.splitScalar(u8, value, '\n');
    var fence: u8 = 0;
    var fence_length: usize = 0;
    var first = true;
    while (lines.next()) |line| {
        if (!first) try output.append(allocator, '\n');
        first = false;
        const trimmed = std.mem.trimStart(u8, line, " ");
        if (line.len - trimmed.len <= 3 and trimmed.len >= 3 and (trimmed[0] == '`' or trimmed[0] == '~')) {
            var count: usize = 0;
            while (count < trimmed.len and trimmed[count] == trimmed[0]) : (count += 1) {}
            if (fence == 0 and count >= 3) {
                fence = trimmed[0];
                fence_length = count;
            } else if (fence == trimmed[0] and count >= fence_length and std.mem.trim(u8, trimmed[count..], " \t\r").len == 0) {
                fence = 0;
            }
        }
        if (fence != 0 and line.len == 0) try output.append(allocator, ' ') else try output.appendSlice(allocator, line);
    }
    return output.toOwnedSlice(allocator);
}

pub fn textWidth(cx: *ui.Cx, value: []const u8, size: f32, weight: u16) f32 {
    var width: f32 = 1;
    var lines = std.mem.splitScalar(u8, value, '\n');
    while (lines.next()) |line| {
        const visual = cx.text.visualLine(.{ .text = line, .font_family = "system", .font_size = size, .font_weight = weight, .use_monospace = true }) catch {
            width = @max(width, cx.text.measureTextWidth(line, size, weight, false) * 1.25 + 1);
            continue;
        };
        width = @max(width, visual.width + 1);
    }
    return width;
}

/// Stable completed Markdown blocks with one mutable tail. Parsing of each
/// chunk uses the same renderer as a completed message (fences/tables/images).
pub const Retained = struct {
    cx: *ui.Cx,
    scope: *ui.Scope,
    root: *ui.Node,
    chunks: std.ArrayList(Chunk) = .empty,
    selection: *@import("ai_text_selection.zig").Selection = undefined,
    width: f32 = 0,
    const Chunk = struct { root: *ui.Node, scope: *ui.Scope, source: []const u8, owned: *ui.Signal([]const u8), selection_start: usize, plain: ?*ui.Node = null, code: ?*CodeState = null };
    pub fn mount(cx: *ui.Cx, scope: *ui.Scope) !*Retained {
        const self = try scope.createState(Retained, .{ .cx = cx, .scope = scope, .root = try ui.box(cx, S.assistantMessage(), .{}) });
        self.selection = try @import("ai_text_selection.zig").retained(cx, scope, self.root);
        try scope.onCleanup(Retained, self, cleanup);
        return self;
    }
    fn cleanup(self: *Retained) void {
        self.chunks.deinit(self.cx.allocator);
    }
    fn truncate(self: *Retained, count: usize) void {
        while (self.chunks.items.len > count) {
            const old = self.chunks.pop().?;
            self.selection.truncate(old.selection_start);
            self.cx.detachChild(self.root, old.root);
            old.scope.dispose();
            self.cx.destroyDetached(old.root);
        }
    }
    pub fn update(self: *Retained, source: []const u8, width: f32, images: ?@import("../../attachments/view/ai_transcript_images.zig").Context) !void {
        if (self.width != width) self.truncate(0);
        self.width = width;
        var start: usize = 0;
        var offset: usize = 0;
        var slot: usize = 0;
        var fence: u8 = 0;
        var fence_len: usize = 0;
        while (offset < source.len) {
            const end = if (std.mem.indexOfScalarPos(u8, source, offset, '\n')) |pos| pos + 1 else source.len;
            const complete = source[end - 1] == '\n';
            const line = std.mem.trim(u8, source[offset..end], " \t\r\n");
            var closed = false;
            if (std.mem.startsWith(u8, line, "```") or std.mem.startsWith(u8, line, "~~~")) {
                var count: usize = 0;
                while (count < line.len and line[count] == line[0]) : (count += 1) {}
                if (fence == 0) {
                    fence = line[0];
                    fence_len = count;
                } else if (fence == line[0] and count >= fence_len and std.mem.trim(u8, line[count..], " \t\r").len == 0) {
                    fence = 0;
                    closed = true;
                }
            }
            if (complete and fence == 0 and (line.len == 0 or closed)) {
                try self.chunk(&slot, source[start..end], width, images);
                start = end;
            }
            offset = end;
        }
        try self.chunk(&slot, source[start..], width, images);
        self.truncate(slot);
    }
    fn chunk(self: *Retained, slot: *usize, text: []const u8, width: f32, images: ?@import("../../attachments/view/ai_transcript_images.zig").Context) !void {
        if (std.mem.trim(u8, text, " \t\r\n").len == 0) return;
        const index = slot.*;
        slot.* += 1;
        if (index < self.chunks.items.len and std.mem.eql(u8, self.chunks.items[index].source, text)) return;
        if (index + 1 == self.chunks.items.len) {
            const old = &self.chunks.items[index];
            if (old.code) |code| if (codeParts(text)) |parts| {
                if (std.mem.eql(u8, code.language.peek(), parts.language)) {
                    try code.update(parts.code, parts.source);
                    old.owned.set(text);
                    old.source = old.owned.peek();
                    return;
                }
            };
        }
        if (index + 1 == self.chunks.items.len and plainSource(text)) {
            const old = &self.chunks.items[index];
            if (old.plain) |node| {
                try node.setTextContent(self.cx.allocator, text);
                old.owned.set(text);
                old.source = old.owned.peek();
                return;
            }
        }
        self.truncate(index);
        const scope = try self.scope.childScope();
        errdefer scope.dispose();
        const owned = try scope.createText(text, .{});
        var code_state: ?*CodeState = null;
        const root = try mountContent(self.cx, scope, owned.peek(), width, images, false, &code_state);
        errdefer self.cx.destroyDetached(root);
        try self.chunks.ensureUnusedCapacity(self.cx.allocator, 1);
        try self.root.appendChild(self.cx.allocator, root);
        const selection_start = self.selection.entries.items.len;
        try self.selection.append(scope, root);
        self.chunks.appendAssumeCapacity(.{ .root = root, .scope = scope, .source = owned.peek(), .owned = owned, .selection_start = selection_start, .plain = if (plainSource(text)) plainNode(root, text) else null, .code = if (codeParts(text) != null) code_state else null });
    }
};

fn plainSource(text: []const u8) bool {
    return text.len != 0 and std.mem.trim(u8, text, " ").len == text.len and std.mem.indexOfAny(u8, text, "\n\r\t`*_[]<>#!|~\\-+.") == null;
}
fn plainNode(root: *ui.Node, text: []const u8) ?*ui.Node {
    if (root.getText()) |value| if (value.spans.len == 0 and std.mem.eql(u8, value.content, text)) return root;
    for (root.children.items) |child| if (plainNode(child, text)) |node| return node;
    return null;
}

const CodeParts = struct { language: []const u8, code: []const u8, source: []const u8 };
fn codeParts(text: []const u8) ?CodeParts {
    const first_end = std.mem.indexOfScalar(u8, text, '\n') orelse return null;
    const first = std.mem.trim(u8, text[0..first_end], " \t\r");
    if (!std.mem.startsWith(u8, first, "```") and !std.mem.startsWith(u8, first, "~~~")) return null;
    var length: usize = 0;
    while (length < first.len and first[length] == first[0]) : (length += 1) {}
    const start = first_end + 1;
    var offset = start;
    while (offset < text.len) {
        const end = std.mem.indexOfScalarPos(u8, text, offset, '\n') orelse text.len;
        const line = std.mem.trim(u8, text[offset..end], " \t\r");
        var count: usize = 0;
        while (count < line.len and line[count] == first[0]) : (count += 1) {}
        if (count >= length and std.mem.trim(u8, line[count..], " \t\r").len == 0) {
            if (std.mem.trim(u8, text[end..], " \t\r\n").len != 0) return null;
            const code_end = if (offset > start and text[offset - 1] == '\n') offset - 1 else offset;
            return .{ .language = first[length..], .code = text[start..code_end], .source = text[start..offset] };
        }
        offset = @min(text.len, end + 1);
    }
    return .{ .language = first[length..], .code = text[start..], .source = text[start..] };
}
