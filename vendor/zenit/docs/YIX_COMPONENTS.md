# 用 Yix 写内置组件

`src/ui/components` 里的内置组件视图用 Yix 书写（`NAME.yix`），样式写在 `styles.yss`。
公共 API（`W.X(.{ … })`、`.mount(scope, cx)`、可作为 `ui.view` 子元素）与手写 Zig 组件一致。
语言本身见 [YIX_REFERENCE.md](YIX_REFERENCE.md)，YSS 见 [YSS.md](YSS.md)，双胞胎生成物的规则见 YIX_REFERENCE §1。

## 架构决策

| 问题 | 决定 | 理由 |
|---|---|---|
| 组件状态的生命周期 | `ui.view.Component` 在调用方 scope 下开子 scope 运行组件函数，子 scope 绑在根节点上；新增 `.mount(scope, cx)` | 与手写 builder 的 `childScope + bindScopeToNode` 同一合同：节点被 `freeNode` 时组件建的 signal / memo / effect 一并销毁。之前组件状态挂在调用方 scope 上，会比节点活得久 |
| 静态 props 的成本 | Yix `computed` 只依赖参数时生成 `ui.Source`：依赖全静态直接得静态值；`view.text` fmt、`show` / `match` / `dynamic` 在源此刻静态时一次定型 | 手写组件的「静态 props 不建 memo / effect」性质；Source 在编译期不知道静态与否，必须在运行期判断 |
| DevTools 组件名 | 生成代码给根节点写 `component_name = "<组件名>"`；组件索引扫 `.yix` 里的 `fn Name(...) View`，跳过有同名 `.yix` 的生成物 | 组件树显示与手写版一致；「跳转源码」落在 `.yix` 而不是生成文件 |
| 样式 | `styles.yss` 的 `recipe` / `style` / `mixin` 生成 `ui.sva` / `ui.cva` / `ui.css` 对象字面量（或 `ui.paramStyle`），token 值生成 `ui.tokenRef(类别, "名字")` 引用 | 视觉只从 style 一个入口进；token 换主题自动跟随 |

## 主题跟随与已知成本

- 运行期解析的样式（`S.X.slot(.root, .{ .status = status })`、`styleBy`，参数是组件 prop）在数据源此刻
  全静态时不建 effect：样式状态挂到节点的 `view_theme` 槽（`core/node.zig` 的 `ViewThemeReplay`），
  `setTheme` 时重放。这个槽与组件自己的 `on_theme` 分开，互不占用；同一节点上第二层运行期样式
  （例如 attrs 叠加到已有运行期样式的组件根）占不到槽时退回 effect。解除按节点代际句柄确认，
  样式 scope 与节点谁先释放都安全（`view_tests.zig` 三个用例，带反向变异验证）。
- 每个组件实例多一个子 scope（生命周期合同的代价，手写 builder 本来也是如此）。

## 组件目录约定

- `NAME.yix`：视图；`styles.yss`：样式配方（引用主题 token）；`.yix` 里写 `const S = @import("styles.yss");`。
- `mod.zig` 手写：公共类型、`pub const X = @import("_NAME.yix.zig").X`、测试；**不并入 `.yix`**。
- 双胞胎 `_NAME.yix.zig` / `_styles.yss.zig` 与源一起提交（`zig build` 会自动重新生成，CI 检查）。
- **放哪里**：`styles.yss` 只放视觉——样式、配方、绘制函数（canvas 的 `draw`）、绘制要的数据结构；
  `.yix` 放视图与视图辅助——a11y 语义函数、列表行 key、文案格式化、由参数派生数据（例如 Divider 的形态）；
  `mod.zig` 放公共类型、导出与测试。
- **命名**：样式 / 插槽 / 维度 snake_case、配方 PascalCase、不加 `Style` 后缀（YSS 编译器检查）；组件的文字参数统一叫 `label` 并声明为 `Text`。
- **computed**：只给被多处引用、或要传给样式参数 / 子组件的派生值起名；模板里只用一次的条件直接内联
  （`{if (label.len != 0) …}`，模板表达式同样静态提升）。同一个谓词出现多次时起一个名字复用，别各写一遍。

## 新写或改写一个组件

1. 视图写进 `NAME.yix`，样式写进 `styles.yss`；随组件参数变化的值写参数化样式（`style name($p: T) { … }`，视图里 `S.name.of(…)`），
   只有 Zig 才算得出来的（读主题数值做算术、调用方的运行期覆盖合并）写照搬的 Zig 函数配 `ui.view.styleBy`。
2. `mod.zig` 只留公共类型、`pub const X = @import("_NAME.yix.zig").X` 与测试。
3. 测试按语义断言（文本内容、样式值、组件名），不依赖内部节点层级；保留 OOM sweep。
4. 验证：
   - `zig build test-ui`（组件单测与 OOM sweep）、`zig build test-headless`；
   - `bash scripts/storybook_pixel_diff.sh` 对比改动前的基线：确定性 story 0 像素差；
   - 静态 props 不建 memo、不建 effect；
   - 送 GLM 交叉审查后再合入。

## 进度

| 组件 | 状态 | 备注 |
|---|---|---|
| Badge / StatusBadge | 完成 | 逐像素一致；Badge 根节点自己承载文字（`<text box={…}>`），保持「按 test_id 查到的节点带文本」的契约（e2e 抓出的第一版回归） |
| VStack / HStack / Spacer | 完成 | 逐像素一致；`children: View` 插槽；Spacer 改为视图组件（原 `Spacer().build(ctx)` 无外部调用方） |
| Tag | 完成 | 逐像素一致；颜色混合改用 `ui.mix`；关闭图标资源在挂载时取值（组件形态的辅助元素）；关闭按钮 hover 淡入由 `.transition` 声明（与手写版同为 150ms ease-out） |
| Alert | 完成 | 逐像素一致；播报级别与内容改为响应式 a11y 字段（live_text 指向源文本，投影按内容哈希判断变化）；关闭按钮 hover 用 `.transition`。revamp 后新增行内操作（`actionLabel` / `actionIconAsset` / `onAction`） |
| Timeline | 完成 | 行是 Yix 组件 `TimelineRow`；列表改为 keyed `{for}`（行 key = 内容 + 借用字符串地址，`mod.rowKey`），最后一行由下标判定——列表变长时原最后一行复用并长出连接线，不再整体重建 |
| Checkbox | 完成 | 逐像素一致；受控值 + 只读 indeterminate；tone 变体 = 勾选（含半选）× 禁用；方框底色 / 边框色 150ms 过渡（边框色从变化前的颜色插值）；对勾资源在挂载时取值 |
| Switch | 完成 | 逐像素一致；受控值 `Model(bool)`、`onClick={if (!disabled) checked = !checked}`、焦点环与 Tab 序声明式；滑块位移与轨道 / 滑块颜色由 200ms 过渡（手写版用 before_render 按位移插值）；标签颜色经 `color` 过渡 |
| Radio / RadioGroup | 完成 | 逐像素一致；行是 Yix 组件 `RadioChoice`（局部 hovered 信号、焦点环）；`value: Model(?[]const u8)` + `onChange: ?Handler([]const u8)`，只报落地的非空值；keyed `{for}` 的 key 取（value, label, disabled） |
| Card | 完成 | 逐像素一致；外观 = cva（变体 × 选中 × 可悬停，悬停高亮写成 compound 里的 `_hover`）+ `styleBy` 尺寸；标题 / 副标题为 `<text box>`（文本节点自带行高），动态为空时整行移除（手写版是 display:none）；可点击时 a11y 整体为源；`mountBody` 去掉（`viewMount` 的 slot 即内容区） |
| Skeleton | 完成 | shimmer 改用 `ui.view.loop`（2s 往返，按墙钟时间；手写版按帧计数，帧率不同速度不同）；根节点统一为带 loading 语义的列（count = 1 时也包一层，布局逐像素一致；storybook 截图只差 1 个色阶，是 shimmer 相位从帧计数改成墙钟时间）；个数可来自信号 |
| Spinner | 完成 | 自绘 canvas；关键帧改为纯函数 `arcAt(now_ms)`；颜色缺省在绘制时取主题强调色（手写版挂载时定死，换主题不变）|
| Progress | 完成 | 确定模式填充用 `styleBy`（宽度百分比 + 三段渐变），不定模式光泽条用 canvas；a11y 整体为源（确定报数值、不定报 busy）；逐像素一致（不定态是动画） |
| ControlShell | 完成 | 纯布局 + 样式基座（control_shell.yix + styles.yss）：`Tone` 配方（variant）× `SizeRecipe`（size）+ 参数化 `geometry` / `pointer` / `chrome`；`:hover` / `:active` / `:focus` 由节点驱动，disabled / invalid / expanded / selected 来自参数，`pins: ui.view.Pins` 经 `ui.view.atMount` 钉住交互态；三个可选插槽 `icon` / `content` / `append`（`?View`，不传不建槽盒）；`rootStyle` 经 cva `.merge(layers)` 逐状态并进色调。取代命令式 `controlShell` / `ControlShellConfig` / `ControlShellRecipe` / `asSlot` / `syncGroupedControlShell` 与 `useAnimatedBackground`；Input / Textarea / Select / SelectHeadless / DatePicker / DateRangePicker / Chip / Button 组合它 |
| Chip | 完成 | chip.yix 组合 ControlShell（icon = 前置图标、content = 标签、append = 关闭钮）；外观 = `Chip` 插槽配方的 `look`（variant × selected × disabled），hover / press 只在可交互（非只读、未禁用）时；Zig 调用方 props 与手写版同名（`label` / `size` / `variant` / `selected` / `disabled` / `icon_asset` / `closable` / `readonly` / `on_click` / `on_close`），`ChipBuilder` 与 `ChipRecipe` 删除 |
| Button | 完成 | 组合 ControlShell（`<ControlShell tag={.button} iconFit={.glyph} …>`）：外框、色调、几何与悬停 / 按下 / 聚焦 / 禁用态都由外壳在节点上声明式解析；icon 槽放 svg / 纹理图标与 loading 环，content 槽放标签，槽的显隐随数据（`iconVisible` / `contentVisible`）。标签、图标（`tintBy` 返回 null = currentColor）、loading 环（`DrawContext.current_color`）都继承外壳根的前景色，状态变化时由框架重画，不再有 Button 自己的 hover / pressed 信号。`base_style` / `hover_style` / `pressed_style` 经 `rootStyle` 逐状态并进外壳的 tone（`.merge`）；`look`（`ui.view.Look`：YSS 样式 / 配方部件，按主题解析）经 `rootLook` 同样并入，排在它们之后。相对 4bbc7e44 的行为差异：根节点 tag 为 `.button`；`base_style` 的全部字段都生效（此前根样式只取白名单字段，如 `overflow_hidden` 被忽略）；边框颜色与背景一起过 150ms（外壳的 fade）；悬停层里的 `border.radius` 不再改变圆角（此前通知卡片 Send 按钮悬停时圆角 6→7）；新增 `pill` |
| Breadcrumb | 完成 | 每一级是行组件 `Crumb`（链接 + 分隔符），最后一级由下标源判定（路径变短时复用的级改报当前页）；按（id, label）内容作 key；子节点从扁平的「链接 / 分隔符」变为每级一行（外层与行内都是 gap 4，几何等价） |
| Steps | 完成 | 不足两步时不画轨道 / 进度段（0 步不再留一条空轨道）；横向 / 纵向两种行组件 `HStep` / `VStep`，状态由下标源与 current 派生（只改外观、步不重建）；圆圈仍是带居中文本的节点自身（`<text box>`），给了对勾图标时已完成步换成「盒子 + 图标」（先按有无图标静态分支，没给图标时不建锚点）；连接线 / 进度段用 `styleBy`；按（标题、描述）内容 + 地址作 key |
| Divider | 完成 | 逐像素一致；线条颜色改为跟随主题（手写版挂载时定死 border_strong，换主题不变）；虚线段改 `view.repeat`（不需要 keyed 列表）；label 为空的响应式标签不再留空标签行 |
| Menu（行视图） | 完成 | 菜单项与分隔线改为 Yix（`MenuEntry` / `MenuSeparator`，menu.yix）；虚拟高亮从「直接改节点背景」改为 `MenuState.highlighted` 信号驱动行样式；浮层、键盘导航、选择管线与 `MenuState` API 不变；逐像素一致 |
| Modal（面板） | 完成 | 对话框面板（标题栏 + 关闭按钮 + 正文插槽）改为带插槽的 Yix 组件 `ModalPanel`；标题与对话框 a11y 名字仍由 `bindTextLabel` 单一写入（名字指向文字节点副本）；浮层 / 开关管线 / 焦点陷阱在 mod.zig；顺带修了 view 里 `<text box={样式函数}>` 丢 comptime 的既有 bug |
| ConfirmDialog | 完成（手写 Zig） | Modal 的确认预设：标题、说明、插槽（子元素）、取消 + 确认；`tone` danger / primary；焦点在取消；`<W.ConfirmDialog open={…} title=… message={…} confirmLabel=… onConfirm={…} onCancel={…}>…</W.ConfirmDialog>` |
| Pressable（新增） | 完成（手写 Zig） | 无默认外观的按钮语义根 + children 插槽（`src/ui/components/pressable/mod.zig`）：内容由调用方决定的行按钮（导航行、概览行）不必再往 Button 根节点里追加子节点。test_id / style 落在可点击的根上（Badge 的教训），`disabled` 门控点击与 Tab 序，`look` 与 Button 同为 `ui.view.Look`（YSS style / recipe，随主题重解析），经默认 cva（行布局 + pointer / disabled 时 not-allowed 光标）的 `.merge` 按根自身状态逐层解析；具体值的 ConditionalStyle 不再接受（编译期报错指向迁移方式，见 docs/design/component-look-follows-theme.md）。写成 Zig 而不是 `.yix`：根节点只有几行，且不进 LP3 等价性夹具（新增夹具要另行评审并重新生成 golden）。Button 本身不变：`ui.view.with(W.Button(…), 子元素)` 改为编译期报错并指向 Pressable |
| Kbd（新增） | 完成（手写 Zig + styles.yss） | 快捷键键帽行（`src/ui/components/kbd/mod.zig`）：`keys` 源经 `v.eachWith` 逐键一个文本节点，键帽盒 `KbdCap` / 文字 `KbdLabel` 两个配方按 `size` × `tone` 解析，换主题重解析；视觉沿用 Tag（`md` 圆角、tag 色调 token）加键帽的 2 pt 底边与等宽最小宽度。同 Pressable 写成 Zig，不进 LP3 等价性夹具；没有 Storybook 故事（组件质量矩阵按故事登记，新增故事要同时补矩阵与 e2e 期望） |
| TooltipSurface（新增） | 完成（手写 Zig） | Tooltip 气泡就地绘制（`src/ui/components/tooltip/surface.zig`）：同 Tooltip 面板的 `tooltip_bg` / `tooltip_fg`、`radius.control`、内边距、`shadow.sm`，不建弹层、不参与命中，由调用方布局；`fixed_dark` 固定用浅色方案的 tooltip 色（深底），给盖在视频等不随主题翻转的内容上的常驻读数（ZeroWork KVM 帧率 HUD）；`text` 是源，`font_size` / `wrap` 挂载时读取 |
| HintCapsule（新增） | 完成（手写 Zig） | 通知文字提示胶囊就地绘制（`src/ui/components/notification/inline_hint.zig`）：同 `Notifier.hint` 的 GlassBox、36 高、圆角 18、内边距 16、13 号字、success / error 圆片，单行省略；不进窗口级通知栈、不参与命中，位置 / 计时 / 淡出归调用方；`max_width` 是源（上限 480）。给属于某个表面而非整个窗口的提示（ZeroWork KVM 画面底部提示条） |
