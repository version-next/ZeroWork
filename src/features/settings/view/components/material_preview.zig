//! 行内材质预览（外观与主题 › 背景图片，`settings.background.preview` 里的图层）：复用宿主的窗口材质图层
//! （`shell/view/background_layers.zig`，与主窗口的背景图片、模糊、透明度同一套绘制，预览与真实效果不会漂移）。
//! 它是宿主经 `Frame.appearance.mount_material_preview` 提供的命令式挂载（纹理在宿主手里），这里只做 `ui.view.component`
//! 适配，不改外观（例外 S-18，类别 b：渲染到原生材质 / GPU 纹理的部分）。宿主没有提供时（测试夹具、预览 runner）挂一个空盒子。
const ui = @import("ui");
const Frame = @import("../window_frame.zig").Frame;

pub const MaterialPreviewProps = struct { frame: ui.Source(*Frame) };

fn mount(props: MaterialPreviewProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const frame = props.frame.peek();
    const appearance = frame.appearance orelse return ui.box(cx, .{}, .{});
    const mount_preview = appearance.mount_material_preview orelse return ui.box(cx, .{}, .{});
    // 宽 0 = 跟随父容器，高 116（同旧 `materialInlinePreview`）。
    const node = try mount_preview(appearance.context, cx, scope, 0, 116);
    node.meta.ownership.meta.test_id = "settings.background.preview.image";
    return node;
}

pub fn MaterialPreview(props: MaterialPreviewProps) ui.view.ComponentOf(mount) {
    return ui.view.component(mount, props);
}
