//! 设置窗口的保存作用域与保存状态机（H-save，人工验收反馈第 4 条）。设计说明与转移表见
//! `docs/ui-revamp/YIX_SPIKE.md`“保存状态机（H-save）”。
//!
//! - **作用域**：右侧当前显示的子页（没有子页的分类就是整个分类页；概览页没有可编辑字段；搜索结果跨分类，
//!   作用域是全部字段）。脏状态、保存、撤销、恢复默认都只针对它。
//! - **离开**：切换分类 / 子页 / 历史、清空搜索时，若草稿里有目标作用域之外的改动，先确认（保存 / 放弃 /
//!   继续编辑）。由此草稿里的改动永远只属于当前作用域。
//! - **恢复默认**：只在当前作用域的值与默认值不同时可点（“有变化”按“相对默认值有变化”理解），确认后只把
//!   当前作用域的字段改回默认值（仍是草稿，保存后生效）。
//!
//! 本文件是纯函数（不依赖 zenit `ui`，不读 Controller）；view-model 把 Controller 的状态喂进来、按结果发 Effect。
const std = @import("std");
const catalog = @import("catalog.zig");
const history = @import("settings_history.zig");
const decisions = @import("intent.zig");
const schema = catalog.schema;
const config = catalog.config;

pub const Location = history.Location;
pub const FieldSet = schema.FieldSet;

// ── 作用域 ──

/// 右侧显示的是什么：位置，是否在搜索，是否是子页面模式（设置窗口恒为 true；嵌在主窗口里的旧页面没有子页面）。
pub const Where = struct {
    location: Location,
    searching: bool = false,
    drill_down: bool = true,

    pub fn eql(a: Where, b: Where) bool {
        if (a.searching or b.searching) return a.searching == b.searching;
        return a.drill_down == b.drill_down and a.location.page == b.location.page and std.meta.eql(a.location.sub, b.location.sub);
    }
};

const max_subpages = blk: {
    var most: usize = 0;
    for (catalog.categories) |category| most = @max(most, category.subpages.len);
    break :blk most;
};

fn pageNamed(comptime name: []const u8) usize {
    for (catalog.pages.pages, 0..) |page, index| if (std.mem.eql(u8, page.name, name)) return index;
    @compileError("settings page not in catalog: " ++ name);
}

/// 每个分类每个子页面（没有子页面的分类用第 0 格）编辑的字段。复合字段：快捷键表归“快捷键”，服务提供方
/// （连同会随提供方增删改变的默认提供方）归“AI 辅助 › 服务提供方”，技能与 MCP 归“AI 辅助 › 技能与 MCP”，
/// 插件偏好归“协议插件”。编译期核对：每个字段恰好落在一个子页面（默认提供方另外也在“行为与权限”）。
const table: [catalog.categories.len][@max(max_subpages, 1)]FieldSet = blk: {
    @setEvalBranchQuota(200_000);
    var result: [catalog.categories.len][@max(max_subpages, 1)]FieldSet = @splat(@splat(.empty));
    for (schema.fields, 0..) |entry, index| {
        const page = pageNamed(entry.page);
        if (catalog.categories[page].subpages.len == 0) {
            result[page][0].set(index);
            continue;
        }
        const sub = catalog.forKey(page, entry.section, entry.key) orelse
            @compileError("settings field has no subpage: " ++ entry.section ++ "." ++ entry.key);
        result[page][sub].set(index);
    }
    result[pageNamed("快捷键")][0].set(schema.keys_index);
    result[pageNamed("协议插件")][0].set(schema.plugin_preferences_index);
    result[pageNamed("AI 辅助")][0].set(schema.providers_index);
    result[pageNamed("AI 辅助")][0].set(schema.find("ai", "default_provider").?);
    result[pageNamed("AI 辅助")][2].set(schema.extensions_index);
    break :blk result;
};

/// 当前作用域的字段。概览页（有子页面的分类、没选子页面）为空；搜索结果为全部字段。
pub fn fieldsAt(where: Where) FieldSet {
    if (where.searching) return FieldSet.full;
    const page = where.location.page;
    if (page >= catalog.categories.len) return .empty;
    const category = catalog.categories[page];
    // 协议插件（F-set-plugins）：列表页没有可编辑字段；插件偏好归各插件的详情页（复合字段，所有详情页共用）。
    if (where.drill_down and history.isDynamic(page) and where.location.sub == null) return .empty;
    if (category.subpages.len == 0) return table[page][0];
    if (!where.drill_down) {
        var all: FieldSet = .empty;
        for (0..category.subpages.len) |sub| all.setUnion(table[page][sub]);
        return all;
    }
    const sub = history.validSubpage(page, where.location.sub) orelse return .empty;
    return table[page][sub];
}

/// 作用域有没有可编辑的字段（概览、“位置与凭据”“导出与清理”没有：不显示“恢复默认”）。
pub fn editable(where: Where) bool {
    return fieldsAt(where).count() != 0;
}

/// 从 `from` 去 `to` 之前要不要确认：草稿里有 `to` 作用域之外的改动时要。
pub fn leaveNeedsConfirm(dirty: FieldSet, to: Where) bool {
    var outside = dirty;
    outside.setIntersection(fieldsAt(to).complement());
    return outside.count() != 0;
}

/// 当前作用域里有没有与默认值不同的字段（“恢复默认”可点）。
pub fn differsFromDefaults(draft: config.Config, where: Where) bool {
    if (where.searching) return false;
    const defaults = config.resetDefaults();
    var it = fieldsAt(where).iterator(.{});
    while (it.next()) |index| if (!schema.fieldEqual(draft, defaults, index)) return true;
    return false;
}

// ── Save Bar 的投影 ──

/// `Controller.State` 的同形（本文件不 import Controller）。
pub const Phase = enum { clean, dirty_valid, dirty_invalid, saving, save_failed };

pub const BarInput = struct {
    phase: Phase,
    /// 草稿有未保存的改动（含无效原文）。
    dirty: bool,
    /// 外观 worker 正在准备主题 / 背景。
    appearance_busy: bool = false,
    /// 字体校验有问题。
    font_problem: bool = false,
};
pub const Tone = enum { normal, danger };
pub const Bar = struct {
    /// 只有草稿有改动（或正在保存）时出现；干净时没有任何常驻状态。
    shown: bool,
    message: []const u8,
    tone: Tone = .normal,
    save_enabled: bool,
    revert_enabled: bool,
};

pub fn bar(input: BarInput) Bar {
    const saving = input.phase == .saving;
    const shown = input.dirty or saving;
    const message: []const u8, const tone: Tone = switch (input.phase) {
        .saving => .{ "正在保存…", .normal },
        .save_failed => .{ "保存失败，草稿已保留", .danger },
        .dirty_invalid => .{ "有设置需要修正", .danger },
        .dirty_valid, .clean => .{ "未保存", .normal },
    };
    return .{
        .shown = shown,
        .message = message,
        .tone = tone,
        // 无效草稿也可点：view-model 据此定位问题，不写盘。
        .save_enabled = input.dirty and !saving and !input.appearance_busy and !input.font_problem,
        .revert_enabled = input.dirty and !saving and !input.appearance_busy,
    };
}

// ── 确认与保存后的去向 ──

/// 当前打开的确认对话框。
pub const Prompt = enum { none, close, leave, reset };
/// 保存成功后要做的事（“保存关闭”、离开前的“保存”）。
pub const AfterSave = enum { none, close, leave };
pub const Flow = struct { prompt: Prompt = .none, after_save: AfterSave = .none };

pub const Event = union(enum) {
    /// 关窗（⌘W / Escape / 关闭按钮）时草稿有改动。
    ask_close,
    /// 切换位置时草稿有目标作用域之外的改动（`leaveNeedsConfirm`）。
    ask_leave,
    /// 点“恢复默认…”（`differsFromDefaults` 为真时才可点）。
    ask_reset,
    /// 对话框里的选择。
    choose: decisions.Decision,
    /// 保存流水线回流：`true` 已提交。
    saved: bool,
    /// 保存没有开始（关口拒绝 / 校验无效被拦下 / 宿主提前返回）。
    save_blocked,
};

/// 状态机要求 view-model 执行的动作。
pub const Action = enum {
    none,
    /// 弹出 / 收起对话框（读 `Flow.prompt`）。
    present,
    /// 开始保存（随后 `saved` / `save_blocked`）。
    save,
    /// 开始保存，提交成功后关窗。
    save_and_close,
    /// 放弃草稿并关窗。
    discard_and_close,
    /// 放弃草稿，再执行挂起的导航。
    discard_and_leave,
    /// 收起对话框，挂起的导航作废（搜索框里的文字回到当前搜索词）。
    stay,
    /// 当前作用域恢复默认值（草稿）。
    reset_scope,
    /// 执行挂起的导航（保存已提交）。
    leave,
    /// 关窗（保存已提交）。
    close,
};

pub const Step = struct { flow: Flow, action: Action };

/// 纯转移函数。对话框打开时新的请求被忽略（对话框是模态的）；与当前对话框不符的选择被忽略。
pub fn step(flow: Flow, event: Event) Step {
    const same: Step = .{ .flow = flow, .action = .none };
    switch (event) {
        .ask_close, .ask_leave, .ask_reset => {
            if (flow.prompt != .none) return same;
            const prompt: Prompt = switch (event) {
                .ask_close => .close,
                .ask_leave => .leave,
                else => .reset,
            };
            // 新的确认取代上一次没走完的“保存后去向”（例如字体问题让保存提前返回）。
            return .{ .flow = .{ .prompt = prompt }, .action = .present };
        },
        .choose => |choice| switch (flow.prompt) {
            .none => return same,
            .close => return switch (choice) {
                .save => .{ .flow = .{ .after_save = .close }, .action = .save_and_close },
                .discard => .{ .flow = .{}, .action = .discard_and_close },
                .cancel => .{ .flow = .{}, .action = .present },
                .reset => same,
            },
            .leave => return switch (choice) {
                .save => .{ .flow = .{ .after_save = .leave }, .action = .save },
                .discard => .{ .flow = .{}, .action = .discard_and_leave },
                .cancel => .{ .flow = .{}, .action = .stay },
                .reset => same,
            },
            .reset => return switch (choice) {
                .reset => .{ .flow = .{}, .action = .reset_scope },
                .cancel => .{ .flow = .{}, .action = .present },
                .save, .discard => same,
            },
        },
        .saved => |ok| {
            const after = flow.after_save;
            const next: Flow = .{ .prompt = flow.prompt };
            if (!ok) return .{ .flow = next, .action = .none };
            return .{ .flow = next, .action = switch (after) {
                .none => .none,
                .close => .close,
                .leave => .leave,
            } };
        },
        .save_blocked => return .{ .flow = .{ .prompt = flow.prompt }, .action = .none },
    }
}

// ── 单元测试（纯函数） ──

const testing = std.testing;
fn fieldIndex(section: []const u8, key: []const u8) usize {
    return schema.find(section, key).?;
}

test "settings save scope: every field belongs to exactly one subpage, composites included" {
    for (0..schema.field_count) |i| {
        var owners: usize = 0;
        for (catalog.categories, 0..) |category, page| {
            const subs = @max(category.subpages.len, 1);
            for (0..subs) |sub| if (table[page][sub].isSet(i)) {
                owners += 1;
            };
        }
        const expected: usize = if (i == fieldIndex("ai", "default_provider")) 2 else 1;
        try testing.expectEqual(expected, owners);
    }
}

test "settings save scope: subpage, whole page, overview and search scopes" {
    const connection = fieldsAt(.{ .location = .{ .page = 2, .sub = 0 } });
    try testing.expect(connection.isSet(fieldIndex("ssh", "keepalive_sec")));
    try testing.expect(!connection.isSet(fieldIndex("ssh", "socks_port")));
    // 概览页没有可编辑字段。
    try testing.expectEqual(@as(usize, 0), fieldsAt(.{ .location = .{ .page = 2 } }).count());
    try testing.expect(!editable(.{ .location = .{ .page = 7, .sub = 0 } }));
    try testing.expect(editable(.{ .location = .{ .page = 7, .sub = 1 } }));
    // 没有子页面的分类：整页。
    try testing.expect(fieldsAt(.{ .location = .{ .page = 1 } }).isSet(schema.keys_index));
    try testing.expect(fieldsAt(.{ .location = .{ .page = 8 } }).isSet(fieldIndex("updates", "auto_check")));
    // 嵌在主窗口里的旧页面（没有子页面）：整个分类。
    const whole = fieldsAt(.{ .location = .{ .page = 2 }, .drill_down = false });
    try testing.expect(whole.isSet(fieldIndex("ssh", "keepalive_sec")) and whole.isSet(fieldIndex("ssh", "otp_modal")));
    // 搜索：全部。
    try testing.expectEqual(@as(usize, schema.field_count), fieldsAt(.{ .location = .{ .page = 0 }, .searching = true }).count());
    // 服务提供方连同默认提供方。
    const providers = fieldsAt(.{ .location = .{ .page = 4, .sub = 0 } });
    try testing.expect(providers.isSet(schema.providers_index) and providers.isSet(fieldIndex("ai", "default_provider")));
}

test "settings save scope: leaving needs confirmation only for changes outside the target" {
    var dirty: FieldSet = .empty;
    try testing.expect(!leaveNeedsConfirm(dirty, .{ .location = .{ .page = 6, .sub = 0 } }));
    dirty.set(fieldIndex("ssh", "keepalive_sec"));
    // 同一子页面、进入搜索：不用确认。
    try testing.expect(!leaveNeedsConfirm(dirty, .{ .location = .{ .page = 2, .sub = 0 } }));
    try testing.expect(!leaveNeedsConfirm(dirty, .{ .location = .{ .page = 0 }, .searching = true }));
    // 同分类的另一个子页面、概览、别的分类：要确认。
    try testing.expect(leaveNeedsConfirm(dirty, .{ .location = .{ .page = 2, .sub = 1 } }));
    try testing.expect(leaveNeedsConfirm(dirty, .{ .location = .{ .page = 2 } }));
    try testing.expect(leaveNeedsConfirm(dirty, .{ .location = .{ .page = 6, .sub = 0 } }));
}

test "settings save scope: reset defaults is available only where the draft differs from defaults" {
    var draft = config.resetDefaults();
    const connection: Where = .{ .location = .{ .page = 2, .sub = 0 } };
    try testing.expect(!differsFromDefaults(draft, connection));
    draft.ssh.socks_port += 1;
    // 别的子页面的值不影响本页。
    try testing.expect(!differsFromDefaults(draft, connection));
    try testing.expect(differsFromDefaults(draft, .{ .location = .{ .page = 2, .sub = 1 } }));
    draft.ssh.keepalive_sec += 1;
    try testing.expect(differsFromDefaults(draft, connection));
    // 概览与搜索结果没有“恢复默认”。
    try testing.expect(!differsFromDefaults(draft, .{ .location = .{ .page = 2 } }));
    try testing.expect(!differsFromDefaults(draft, .{ .location = .{ .page = 2, .sub = 0 }, .searching = true }));
}

test "settings save bar: shown only with unsaved changes; problems keep visible feedback" {
    const clean = bar(.{ .phase = .clean, .dirty = false });
    try testing.expect(!clean.shown and !clean.save_enabled and !clean.revert_enabled);
    const dirty = bar(.{ .phase = .dirty_valid, .dirty = true });
    try testing.expect(dirty.shown and dirty.save_enabled and dirty.revert_enabled);
    try testing.expectEqualStrings("未保存", dirty.message);
    const invalid = bar(.{ .phase = .dirty_invalid, .dirty = true });
    try testing.expect(invalid.shown and invalid.save_enabled and invalid.tone == .danger);
    const failed = bar(.{ .phase = .save_failed, .dirty = true });
    try testing.expect(failed.shown and failed.tone == .danger and failed.save_enabled);
    const saving = bar(.{ .phase = .saving, .dirty = true });
    try testing.expect(saving.shown and !saving.save_enabled and !saving.revert_enabled);
    const busy = bar(.{ .phase = .dirty_valid, .dirty = true, .appearance_busy = true });
    try testing.expect(busy.shown and !busy.save_enabled and !busy.revert_enabled);
    const font = bar(.{ .phase = .dirty_valid, .dirty = true, .font_problem = true });
    try testing.expect(!font.save_enabled and font.revert_enabled);
}

test "settings save flow: transition table" {
    const idle: Flow = .{};
    // 请求 → 对话框。
    try testing.expectEqual(Step{ .flow = .{ .prompt = .close }, .action = .present }, step(idle, .ask_close));
    try testing.expectEqual(Step{ .flow = .{ .prompt = .leave }, .action = .present }, step(idle, .ask_leave));
    try testing.expectEqual(Step{ .flow = .{ .prompt = .reset }, .action = .present }, step(idle, .ask_reset));
    // 对话框打开时新的请求被忽略。
    try testing.expectEqual(Step{ .flow = .{ .prompt = .close }, .action = .none }, step(.{ .prompt = .close }, .ask_leave));
    // 关窗确认。
    try testing.expectEqual(Step{ .flow = .{ .after_save = .close }, .action = .save_and_close }, step(.{ .prompt = .close }, .{ .choose = .save }));
    try testing.expectEqual(Step{ .flow = .{}, .action = .discard_and_close }, step(.{ .prompt = .close }, .{ .choose = .discard }));
    try testing.expectEqual(Step{ .flow = .{}, .action = .present }, step(.{ .prompt = .close }, .{ .choose = .cancel }));
    try testing.expectEqual(Step{ .flow = .{ .prompt = .close }, .action = .none }, step(.{ .prompt = .close }, .{ .choose = .reset }));
    // 离开确认。
    try testing.expectEqual(Step{ .flow = .{ .after_save = .leave }, .action = .save }, step(.{ .prompt = .leave }, .{ .choose = .save }));
    try testing.expectEqual(Step{ .flow = .{}, .action = .discard_and_leave }, step(.{ .prompt = .leave }, .{ .choose = .discard }));
    try testing.expectEqual(Step{ .flow = .{}, .action = .stay }, step(.{ .prompt = .leave }, .{ .choose = .cancel }));
    // 恢复默认确认。
    try testing.expectEqual(Step{ .flow = .{}, .action = .reset_scope }, step(.{ .prompt = .reset }, .{ .choose = .reset }));
    try testing.expectEqual(Step{ .flow = .{}, .action = .present }, step(.{ .prompt = .reset }, .{ .choose = .cancel }));
    try testing.expectEqual(Step{ .flow = .{ .prompt = .reset }, .action = .none }, step(.{ .prompt = .reset }, .{ .choose = .save }));
    // 没有对话框时的选择被忽略。
    try testing.expectEqual(Step{ .flow = idle, .action = .none }, step(idle, .{ .choose = .save }));
    // 保存回流：成功执行去向，失败 / 被拦下只清掉去向。
    try testing.expectEqual(Step{ .flow = .{}, .action = .leave }, step(.{ .after_save = .leave }, .{ .saved = true }));
    try testing.expectEqual(Step{ .flow = .{}, .action = .close }, step(.{ .after_save = .close }, .{ .saved = true }));
    try testing.expectEqual(Step{ .flow = .{}, .action = .none }, step(.{ .after_save = .leave }, .{ .saved = false }));
    try testing.expectEqual(Step{ .flow = .{}, .action = .none }, step(.{ .after_save = .leave }, .save_blocked));
    try testing.expectEqual(Step{ .flow = .{}, .action = .none }, step(idle, .{ .saved = true }));
    // 新的确认取代没走完的去向。
    try testing.expectEqual(Step{ .flow = .{ .prompt = .reset }, .action = .present }, step(.{ .after_save = .leave }, .ask_reset));
}
