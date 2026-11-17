//! 外观与主题（第 0 类）`.yix` 面板正文的组件测试（P3 3e 外观包）。
//! 夹具（`appearance_fixture.yix`）挂真实面板 + 真 `ViewModel` + Ports 替身（主题库是真的内置 Registry）；只用 test_id、可见文字、
//! 禁用态、草稿（Controller）与 view-model 的选择器断言，不依赖节点层级（开关滑块的过渡槽除外，同 `settings_panes_tests`）。
const std = @import("std");
const ui = @import("ui");
const kit = @import("../../../shared/testing/ui_kit.zig");
const Controller = @import("../model/settings_controller.zig").Controller;
const RuntimeConfig = @import("../../../config/runtime_config.zig").RuntimeConfig;
const Registry = @import("../../../config/theme_registry.zig").Registry;
const m = @import("../model/view_model.zig");
const values = @import("../model/settings_values.zig");
const Frame = @import("../view/window_frame.zig").Frame;
const fixture = @import("_appearance_fixture.yix.zig");

const Panes = struct {
    env: kit.Headless,
    tmp: std.testing.TmpDir,
    runtime: RuntimeConfig,
    controller: Controller,
    registry: Registry,
    vm: m.ViewModel,
    frame: Frame = undefined,
    effects: std.ArrayList(m.Effect) = .empty,
    busy: bool = false,
    /// 宿主已上传的背景缩略图纹理（`AppearanceStatus.thumbnail`）。
    thumbnail: ?m.Texture = null,
    root: *ui.Node = undefined,

    fn init(self: *Panes, query: []const u8) !void {
        const a = std.testing.allocator;
        self.* = .{ .env = try kit.headless(a, .{ .width = 760, .height = 3600, .root_style = .{ .width = .fill(), .height = .fill(), .direction = .column } }), .tmp = std.testing.tmpDir(.{}), .runtime = undefined, .controller = undefined, .registry = try Registry.init(a), .vm = undefined };
        self.runtime = try RuntimeConfig.loadOrDefault(std.testing.io, self.tmp.dir, a, "config.toml");
        self.controller = try Controller.init(a, self.runtime.value);
        if (query.len != 0) try self.controller.setSearch(query);
        self.vm = m.ViewModel.init(&self.controller, .{ .context = self, .run = run, .allow = allow, .appearance = appearance });
        self.frame = .{ .vm = &self.vm };
        try self.vm.attach(self.env.scope);
        self.root = try ui.view.render(self.env.scope, self.env.cx, fixture.AppearanceFixture(.{ .vm = &self.vm, .frame = &self.frame }));
        try self.env.mount(self.root);
        self.env.frames(2);
    }
    fn deinit(self: *Panes) void {
        self.env.deinit();
        self.effects.deinit(std.testing.allocator);
        self.controller.deinit();
        self.registry.deinit();
        self.runtime.deinit();
        self.tmp.cleanup();
    }
    fn run(raw: *anyopaque, effect: m.Effect) void {
        const self: *Panes = @ptrCast(@alignCast(raw));
        self.effects.append(std.testing.allocator, effect) catch {};
    }
    fn allow(_: *anyopaque, _: m.Gate) bool {
        return true;
    }
    fn appearance(raw: *anyopaque) m.AppearanceStatus {
        const self: *Panes = @ptrCast(@alignCast(raw));
        return .{ .ready = true, .busy = self.busy, .registry = &self.registry, .saved_theme = self.runtime.value.ui.theme, .font_actual = "Monaco", .thumbnail = self.thumbnail };
    }
    fn noop(_: *anyopaque) void {}
    fn node(self: *Panes, id: []const u8) !*ui.Node {
        return kit.expectByTestId(self.root, id);
    }
    fn click(self: *Panes, id: []const u8) !void {
        const rect = (try self.node(id)).globalRect();
        self.env.cx.handleClick(rect.x + rect.w / 2, rect.y + rect.h / 2);
        self.env.frame();
    }
    fn typeInto(self: *Panes, id: []const u8, text: []const u8) !void {
        self.env.cx.setFocus(try self.node(id));
        self.env.cx.handleKeyDown(.a, .{ .super = true });
        self.env.cx.handleTextInput(text);
        self.env.frame();
    }
    fn escape(self: *Panes) bool {
        // 真实窗口：改过的输入框先由原生 Input 回到聚焦时的值（OverlayHost → `Cx.input_escape`），再到宿主分层。
        @import("../../../shared/ui/overlay/overlay_host.zig").install(self.env.cx);
        if (ui.widgets.input.revertFocused(self.env.cx)) {
            self.env.frame();
            return true;
        }
        const focused = self.env.cx.focus_manager.getFocused();
        return self.vm.consumeEscape(if (focused) |owner| self.env.cx.focus_targets.targetName(self.env.cx, owner) else null);
    }
    fn read(self: *Panes, section: []const u8, key: []const u8) values.Value {
        return values.read(self.controller.model.value, section, key).?;
    }
    fn appearanceEffects(self: *Panes, tag: std.meta.Tag(m.AppearanceEffect)) usize {
        var count: usize = 0;
        for (self.effects.items) |effect| if (effect == .appearance and effect.appearance == tag) {
            count += 1;
        };
        return count;
    }
};

fn shown(node: *ui.Node) bool {
    var cursor: ?*ui.Node = node;
    while (cursor) |current| : (cursor = current.parent) if (current.style.display == .none) return false;
    return node.globalRect().h > 0;
}
/// 子树里 a11y 标为不可用的节点数（原生 `W.Tabs` 的不可选项）。
fn disabledItems(node: *ui.Node) usize {
    var count: usize = if (node.behavior.interaction.a11y) |a11y| @intFromBool(a11y.disabled) else 0;
    for (node.children.items) |child| count += disabledItems(child);
    return count;
}
fn isOff(node: *ui.Node) bool {
    const a11y = node.behavior.interaction.a11y orelse return false;
    return a11y.disabled;
}
fn textOf(node: *ui.Node, buffer: []u8) []const u8 {
    var used: usize = 0;
    collect(node, buffer, &used);
    return buffer[0..used];
}
fn collect(node: *ui.Node, buffer: []u8, used: *usize) void {
    if (node.style.display == .none) return;
    if (node.getText()) |value| {
        const n = @min(value.content.len, buffer.len - used.*);
        @memcpy(buffer[used.*..][0..n], value.content[0..n]);
        used.* += n;
    }
    for (node.children.items) |child| collect(child, buffer, used);
}
fn collectNodes(node: *ui.Node, out: *std.ArrayList(*ui.Node)) !void {
    try out.append(std.testing.allocator, node);
    for (node.children.items) |child| try collectNodes(child, out);
}
fn switchThumb(node: *ui.Node) *ui.Node {
    return node.children.items[0].children.items[0];
}
fn translateSlotActive(node: *ui.Node) bool {
    if (node.frame_state.frame_local.runtime.transitions) |slots| if (slots.find(.translate_x)) |slot| return slot.active;
    return false;
}
/// S-11：切换外观页的开关时，整个分类的节点原样保留（指针相同），开关的滑块在走 translate 过渡。
fn expectLocalToggle(p: *Panes, field: []const u8) !void {
    var before: std.ArrayList(*ui.Node) = .empty;
    defer before.deinit(std.testing.allocator);
    try collectNodes(try p.node("settings.appearance"), &before);
    try p.click(field);
    try std.testing.expect(translateSlotActive(switchThumb(try p.node(field))));
    var after: std.ArrayList(*ui.Node) = .empty;
    defer after.deinit(std.testing.allocator);
    try collectNodes(try p.node("settings.appearance"), &after);
    try std.testing.expectEqual(before.items.len, after.items.len);
    for (before.items, after.items) |a, b| try std.testing.expect(a == b);
}

test "settings appearance yix: every pane and field keeps its frozen test id" {
    var p: Panes = undefined;
    try p.init("");
    defer p.deinit();
    for ([_][]const u8{
        "settings.appearance",                    "settings.appearance.themes",          "settings.appearance.themes.summary", "settings.theme.strip",
        "settings.theme.current",                 "settings.theme.remove.current",       "settings.theme.import",              "settings.theme.ansi",
        "settings.appearance.app_icon",           "settings.field.icon_background",      "settings.option.icon_background.light", "settings.appearance.help.icon_background",
        "settings.appearance.materials",          "settings.materials.header",           "settings.appearance.materials.summary", "settings.background.identity",
        "settings.materials.preview.open",        "settings.background.filename",        "settings.background.state",          "settings.background.choose",
        "settings.background.remove",             "settings.background.position_fields", "settings.field.fit",                 "settings.field.alignment",
        "settings.field.transparency",            "settings.slider.transparency",        "settings.field.blur_px",             "settings.appearance.help.transparency",
        "settings.appearance.preview",            "settings.font.preview",               "settings.font.preview.caret",        "settings.font.preview.command",
        "settings.appearance.font",               "settings.field.font_family",          "settings.field.font_size",           "settings.field.line_height",
        "settings.field.cursor_style",            "settings.appearance.help.cursor_style", "settings.appearance.aids",         "settings.toggle.timestamp_gutter",
        "settings.toggle.command_info",           "settings.toggle.input_line_highlight", "settings.toggle.sidebar_collapsed", "settings.field.scrollback_limit",
        "settings.appearance.mini_preview",       "settings.theme.dark",                 "settings.theme.light",               "settings.toggle.enabled",
    }) |id| _ = try p.node(id);
    // 主题：卡片按主题库顺序，当前主题选中（a11y），页头是主题名；ANSI 色板有 16 格。
    var buffer: [512]u8 = undefined;
    try std.testing.expect((try p.node("settings.theme.dark")).behavior.interaction.a11y.?.selected);
    try std.testing.expect(!(try p.node("settings.theme.light")).behavior.interaction.a11y.?.selected);
    try std.testing.expectEqualStrings(p.registry.get("dark").?.theme.name, textOf(try p.node("settings.appearance.themes.summary"), &buffer));
    // 背景未选图片：“尚未选择图片”，移除不可用；路径为空时没有行内材质预览。
    try std.testing.expectEqualStrings("尚未选择图片", textOf(try p.node("settings.background.filename"), &buffer));
    try std.testing.expect(isOff(try p.node("settings.background.remove")));
    try std.testing.expect(kit.findByTestId(p.root, "settings.background.preview") == null);
    // 目录来源才有轮播的两项。
    try std.testing.expect(kit.findByTestId(p.root, "settings.background.rotation_fields") == null);
}

test "settings appearance yix: switches slide in place and edit the draft without remounting the pane (S-11)" {
    var p: Panes = undefined;
    try p.init("");
    defer p.deinit();
    const before = p.read("ui", "command_info").boolean;
    try expectLocalToggle(&p, "settings.toggle.command_info");
    try std.testing.expectEqual(!before, p.read("ui", "command_info").boolean);
    try std.testing.expect(p.vm.isDirty());
    try std.testing.expect(p.appearanceEffects(.changed) >= 1);
    // 工作区缩略预览跟随“默认隐藏侧栏”（同一节点上局部更新）。
    try expectLocalToggle(&p, "settings.toggle.sidebar_collapsed");
    try std.testing.expect(p.read("ui", "sidebar_collapsed").boolean);
    // 背景图片的开启开关在页头：摘要跟着变。
    var buffer: [256]u8 = undefined;
    try std.testing.expect(std.mem.startsWith(u8, textOf(try p.node("settings.appearance.materials.summary"), &buffer), "已关闭"));
    try std.testing.expect(shown(try p.node("settings.field.transparency")));
}

test "settings appearance yix: 浮动卡片切换动画 is a native RadioGroup that edits ui.float_card_transition (Z12b)" {
    var p: Panes = undefined;
    try p.init("");
    defer p.deinit();
    const group = try p.node("settings.field.float_card_transition");
    const anchor = try p.node("settings.option.float_card_transition.anchor");
    const fade = try p.node("settings.option.float_card_transition.fade");
    try std.testing.expect(group.behavior.interaction.a11y.?.role == .radiogroup);
    // 默认“收向所属标签”。
    try std.testing.expectEqualStrings("anchor", p.read("ui", "float_card_transition").text);
    try std.testing.expect(anchor.behavior.interaction.a11y.?.checked.?);
    try std.testing.expect(!fade.behavior.interaction.a11y.?.checked.?);
    var buffer: [128]u8 = undefined;
    try std.testing.expect(std.mem.indexOf(u8, textOf(fade, &buffer), "淡出") != null);
    try p.click("settings.option.float_card_transition.fade");
    try std.testing.expectEqualStrings("fade", p.read("ui", "float_card_transition").text);
    try std.testing.expect(p.vm.isDirty());
    // 同一节点上局部更新，不重挂。
    try std.testing.expect(fade == try p.node("settings.option.float_card_transition.fade"));
    try std.testing.expect(fade.behavior.interaction.a11y.?.checked.?);
    try std.testing.expect(!anchor.behavior.interaction.a11y.?.checked.?);
    // 草稿值经常规写出与解析往返，并映射到 zenit 的原地淡出缩小 token。
    const config = @import("../../../config/config.zig");
    const motion = @import("../../../shared/ui/styles/float_card_motion.zig");
    var draft = config.Config{};
    try values.writeConfig(&draft, "ui", "float_card_transition", .{ .text = "fade" });
    try std.testing.expectEqual(config.FloatCardTransition.fade, config.floatTransitionMode(&draft));
    try std.testing.expectEqual(ui.fx.anchor_transition.Mode.fade_scale, motion.tokens(config.floatTransitionMode(&draft)).mode);
    try std.testing.expectEqual(ui.fx.anchor_transition.Mode.anchor, motion.tokens(config.floatTransitionMode(null)).mode);
}

test "settings appearance yix: theme card selection, preview badge and remove reasons follow the draft" {
    var p: Panes = undefined;
    try p.init("");
    defer p.deinit();
    const strip = try p.node("settings.theme.strip");
    const light = try p.node("settings.theme.light");
    p.vm.dispatch(m.Intent.selectTheme("light"));
    p.env.frame();
    try std.testing.expectEqualStrings("light", p.read("ui", "theme").text);
    try std.testing.expect(light == try p.node("settings.theme.light"));
    try std.testing.expect(strip == try p.node("settings.theme.strip"));
    try std.testing.expect(light.behavior.interaction.a11y.?.selected);
    try std.testing.expect(p.vm.themePreviewing());
    // 当前（草稿）主题是内置的：删除按钮不可用，提示写明原因。
    try std.testing.expect(isOff(try p.node("settings.theme.remove.current")));
    try std.testing.expectEqualStrings("内置主题不可删除", p.vm.themeRemoveReason());
    // 导入经 Command 交宿主。
    try p.click("settings.theme.import");
    var imported = false;
    for (p.effects.items) |effect| imported = imported or effect == .import_theme;
    try std.testing.expect(imported);
}

test "settings appearance yix: numeric fields keep invalid raw text, Escape reverts, transparency rounds on submit" {
    var p: Panes = undefined;
    try p.init("");
    defer p.deinit();
    try p.typeInto("settings.field.transparency", "120");
    try std.testing.expect(shown(try p.node("settings.error.transparency")));
    var buffer: [256]u8 = undefined;
    try std.testing.expect(std.mem.indexOf(u8, textOf(try p.node("settings.error.transparency"), &buffer), "0–100") != null);
    try std.testing.expectEqualStrings("120", p.vm.appearanceText(m.fields.appearance.transparency));
    try std.testing.expect(p.escape());
    p.env.frame();
    try std.testing.expect(!shown(try p.node("settings.error.transparency")));
    try std.testing.expectEqualStrings("0.0", p.vm.appearanceText(m.fields.appearance.transparency));
    // 提交按十分位取整（同旧 `Field.submit`）。
    p.vm.dispatch(m.Intent.appearanceText(m.fields.appearance.transparency.key.?, "12.34"));
    p.vm.dispatch(m.Intent.appearanceSubmit(m.fields.appearance.transparency.key.?, "12.34"));
    try std.testing.expectApproxEqAbs(@as(f32, 12.3), p.read("ui.materials.background", "transparency").decimal, 0.0001);
    // 行高两位小数；没改过就按 Enter 不改值。
    try std.testing.expectEqualStrings("1.50", p.vm.appearanceText(m.fields.appearance.line_height));
    p.vm.dispatch(m.Intent.appearanceSubmit(m.fields.appearance.line_height.key.?, "1.50"));
    try std.testing.expectApproxEqAbs(@as(f32, 1.5), p.read("ui", "line_height").decimal, 0.0001);
    try std.testing.expect(p.appearanceEffects(.validate_font) >= 1);
    // 字号：无效 → 行内提示。
    try p.typeInto("settings.field.font_size", "99");
    try std.testing.expect(shown(try p.node("settings.error.font_size")));
}

test "settings appearance yix: busy host locks the controls, custom font swaps in an input" {
    var p: Panes = undefined;
    try p.init("");
    defer p.deinit();
    p.busy = true;
    p.vm.sync();
    p.env.frame();
    try std.testing.expect(isOff(try p.node("settings.toggle.command_info")));
    // 光标形状分段：三项都不可选（同旧分段在保存 / 宿主忙时不接收点击）。
    try std.testing.expectEqual(@as(usize, 3), disabledItems(try p.node("settings.field.cursor_style")));
    const before = p.read("ui", "command_info").boolean;
    p.vm.dispatch(m.Intent.appearanceValue(m.fields.appearance.command_info.key.?, .{ .boolean = !before }));
    try std.testing.expectEqual(before, p.read("ui", "command_info").boolean);
    p.busy = false;
    p.vm.sync();
    p.env.frame();
    try std.testing.expect(!isOff(try p.node("settings.toggle.command_info")));
    try std.testing.expectEqual(@as(usize, 0), disabledItems(try p.node("settings.field.cursor_style")));
    p.vm.dispatch(m.Intent.appearanceAction(.custom_font));
    p.env.frame();
    try std.testing.expect(p.vm.customFont());
    const field = try p.node("settings.field.font_family");
    try std.testing.expect(field.behavior.interaction.text_input_client != null or kit.findByTestId(field, "settings.field.font_family") != null);
}

test "settings appearance yix: search keeps the legacy per-field filter in the font pane" {
    var p: Panes = undefined;
    try p.init("行高");
    defer p.deinit();
    try std.testing.expect(shown(try p.node("settings.appearance.font")));
    try std.testing.expect(shown(try p.node("settings.field.line_height")));
    // 未命中的行与面板不建（同旧实现；搜索结果页的子树要留在自动化查询的缓冲里）。
    try std.testing.expect(kit.findByTestId(p.root, "settings.field.font_size") == null);
    try std.testing.expect(kit.findByTestId(p.root, "settings.field.font_family") == null);
    try std.testing.expect(shown(try p.node("settings.field.cursor_style")));
    try std.testing.expect(kit.findByTestId(p.root, "settings.appearance.aids") == null);
    try std.testing.expect(kit.findByTestId(p.root, "settings.appearance.themes") == null);
}

test "settings appearance yix: a failed background shows its inline state while the draft is clean (H-save)" {
    var p: Panes = undefined;
    try p.init("");
    defer p.deinit();
    try std.testing.expect(!p.controller.model.dirty);
    p.controller.background.state = .failed;
    p.controller.background.problem = error.NoUsableImages;
    p.vm.sync();
    p.env.frame();
    const state = try p.node("settings.background.state");
    try std.testing.expect(shown(state));
    var buffer: [256]u8 = undefined;
    try std.testing.expectEqualStrings("目录中没有可用图片 · 草稿保留", textOf(state, &buffer));
    try std.testing.expect(p.vm.backgroundFailed());
    p.controller.background.state = .empty;
    p.controller.background.problem = null;
}

test "settings appearance yix: restore defaults takes the same host path as a manual edit (font check, background prep)" {
    var p: Panes = undefined;
    try p.init("");
    defer p.deinit();
    p.vm.dispatch(m.Intent.appearanceValue(m.fields.appearance.font_size.key.?, .{ .unsigned = 18 }));
    try std.testing.expectEqual(@as(u32, 18), p.read("ui", "font_size").unsigned);
    p.effects.clearRetainingCapacity();
    p.vm.dispatch(m.Intent.runCommand(.reset_defaults));
    p.vm.dispatch(m.Intent.decideWith(.reset));
    try std.testing.expectEqual(@as(u32, 14), p.read("ui", "font_size").unsigned);
    try std.testing.expect(p.appearanceEffects(.changed) >= 1);
}

test "settings appearance yix: the theme manager entry (navigate only) mounts the theme panes" {
    var p: Panes = undefined;
    try p.init("");
    defer p.deinit();
    p.vm.remountContent();
    p.vm.sync();
    p.env.frames(2);
    try std.testing.expect(shown(try p.node("settings.appearance.themes")));
    try std.testing.expect(shown(try p.node("settings.theme.strip")));
}

fn findImage(node: *ui.Node) ?*ui.Node {
    if (node.getImage() != null) return node;
    for (node.children.items) |child| if (findImage(child)) |hit| return hit;
    return null;
}

test "settings appearance yix: the background thumbnail draws the host texture (cover, centered) inside its 72 x 48 frame" {
    var p: Panes = undefined;
    try p.init("");
    defer p.deinit();
    const thumb = try p.node("settings.materials.preview.open");
    try std.testing.expect(findImage(thumb) == null);
    // 草稿有背景路径、宿主已上传纹理（200 × 100）：同旧 `mountAppearanceImage`，按 cover 缩到 96 × 48、水平居中。
    // 这条链（`Ports.appearance → AppearanceStatus.thumbnail → vm.backgroundThumbnail → <image>`）是通的；真实窗口里缩略图空白的根因
    // 在纹理归属（主窗口的本地纹理表，设置窗口解析不到），见 `shell/model/background_texture.zig`。
    p.controller.model.value.ui.materials.background.enabled = true;
    const original_path = p.controller.model.value.ui.materials.background.path;
    defer p.controller.model.value.ui.materials.background.path = original_path;
    p.controller.model.value.ui.materials.background.path = "/tmp/zw-thumbnail.png";
    p.thumbnail = .{ .id = 7, .width = 200, .height = 100 };
    p.vm.sync();
    p.env.frames(2);
    const frame = (try p.node("settings.materials.preview.open")).globalRect();
    try std.testing.expectEqual(@as(f32, 72), frame.w);
    try std.testing.expectEqual(@as(f32, 48), frame.h);
    const image = findImage(try p.node("settings.materials.preview.open")) orelse return error.ThumbnailImageMissing;
    try std.testing.expectEqual(@as(u32, 7), image.getImage().?.texture_id);
    try std.testing.expect(shown(image));
    const rect = image.globalRect();
    try std.testing.expectEqual(@as(f32, 96), rect.w);
    try std.testing.expectEqual(@as(f32, 48), rect.h);
    // 定位相对缩略图框的内容盒（框有 1px 描边）：左移 12、顶端对齐。
    try std.testing.expectApproxEqAbs(frame.x + 1 - 12, rect.x, 0.5);
    try std.testing.expectApproxEqAbs(frame.y + 1, rect.y, 0.5);
    // 不着色（白色乘色），否则图片会被染成文字色。
    try std.testing.expectEqual(ui.Color.WHITE, image.getImage().?.tint);
    // 换一张纹理（如轮播 / 重新选择）：跟随新的 id 与尺寸。
    p.thumbnail = .{ .id = 9, .width = 100, .height = 100 };
    p.vm.sync();
    p.env.frames(2);
    const next = findImage(try p.node("settings.materials.preview.open")) orelse return error.ThumbnailImageMissing;
    try std.testing.expectEqual(@as(u32, 9), next.getImage().?.texture_id);
    try std.testing.expectEqual(@as(f32, 72), next.globalRect().w);
    try std.testing.expectEqual(@as(f32, 72), next.globalRect().h);
}
