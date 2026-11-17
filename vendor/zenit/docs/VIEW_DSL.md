# `ui.view`：声明式视图树（Solid 风格 JSX 的 Zig 版）

> 状态：纯 Zig `ui.view` 已落地；第二层 Yix（`.yix` / `.yss` 编译到本层）见 [YIX_REFERENCE.md](YIX_REFERENCE.md)。
> Yix / YSS 是可选的：只用 Zig 写组件（参数、受控值、插槽、配方）的完整示例见 [examples/zig_native](../examples/zig_native/README.md)。
>
> 相关：`docs/SIGNAL_API_DESIGN.md`（Signal-first 组件 API）、`docs/STYLING.md`（样式三层模型）。

## 0. 一页结论

```zig
const v = ui.view;
const W = ui.widgets;

fn mountUI(cx: *ui.Cx, scope: *ui.Scope) !*ui.Node {
    const count = try scope.createSignal(u32, 0);
    const even = ui.map(count, isEven);

    return v.render(scope, cx, v.col(.{ .style = S.root }, .{
        v.text(.{ .style = S.title }, "Reactive Counter"),
        v.text(.{ .style = S.count }, v.fmt("count = {d}", .{count})),
        v.row(.{ .style = S.Badge.of(.{ .even = even }) }, .{
            v.show(even, .{"even"}).fallback(.{"odd"}),
        }),
        v.row(.{ .style = S.buttons }, .{
            W.Button(.{ .label = "+1", .on_click = ui.on.update(count, inc) }),
            W.Button(.{ .label = "Reset", .on_click = ui.on.set(count, 0) }),
        }),
        v.each(todos, .id, todoRow),
    }));
}
```

| 问题（改造前） | 现在 |
|---|---|
| 每个子节点 `try parent.appendChild(allocator, try ...)` | 子元素写成 tuple，`render` 一次挂好 |
| 点一下按钮要 `Bindings` 结构体 + `cx.bindState` + `cx.on` | `ui.on.set / toggle / update / assign / call / bind` |
| `Show` / `For` 要包 `struct { fn build }` | `v.show(cond, .{...})` / `v.each(items, .id, row)`，子元素描述值直接存进区域 |
| 组件 `.mount(scope, cx)` + 取 `result.container / .content` | 组件 builder 直接当子元素；`v.with(组件, .{子元素})` |
| 样式：`boxStyled` 只收一个函数，条件样式要自己写 effect | `.style` 收函数 / 字面量 / tuple 合并 / `when` / `hover` / `styleBy` |

模型不变：**没有 VDOM，组件函数不重跑**。元素是值，`render` 一次性挂成保留模式节点树，之后只有细粒度 effect 更新（与 Solid 一致，也与 SIGNAL_API_DESIGN §1.4 的非目标一致）。

Yix 编译器把声明区与模板拆成持久 setup 和短期 view。手写组件可显式使用 `renderComponentView(setup_scope, cx, typed_context, render_fn)`；该入口保存 context，并以新 view scope 调用 `render_fn(ctx, view_scope, cx, sink)`。仅在测试 / dev preview 中，可于 UI 安全点用 `componentInstance(root).?.rebuild()` 重建同一模板；用实例的 `parts` / live ref 读取新返回值，旧 Node / ViewParts / capture 快照失效。attrs、parts、事件、样式与 slot 描述随新 view 重新绑定，slot 的 scope 仍属于调用方。不能重放的 Node slot 在清理旧 view 前被拒绝；挂载失败清理部分结果并要求重新挂载，取消可能销毁实例。此入口不启用运行时模板替换，详见 [Yix 生命周期契约](YIX_REFERENCE.md#23-状态)。

## 1. 元素

| 元素 | 说明 |
|---|---|
| `v.box(props, children)` / `v.row` / `v.col` | 容器。row / col 的 direction 恒定（样式里的 direction 被覆盖，主题重放时也是） |
| `v.text(props, content)` | content：字符串 / `v.fmt(fmt, args)` / 任意 `[]const u8` 响应式源 |
| `v.spacer()` | 弹性空白 |
| `v.grid(.{ .columns = &tracks, .rows = &tracks, .column_gap, .row_gap, .style, … }, children)` | CSS grid 布局容器（`ui.GridTrackSize`：px / fr / auto）；子项用样式里的 `grid_placement` 跨行列。与 `W.Grid` 虚拟化数据网格不同 |
| `v.portal(元素)` | 挂到窗口浮层 portal（与 Popover 内容同层，压过整棵文档树、不受祖先裁剪），声明处不占位；随声明处 scope 卸载 / 失败回滚回收 |
| `v.show(cond, children).fallback(children)` | 条件渲染；cond 是 bool 或任意 bool 源（`ui.not(x)`、`ui.eq(page, .home)`…） |
| `v.match(value, .{ .a = ..., .b = ..., .@"else" = ... })` | 枚举分支，编译期检查穷尽 |
| `v.each(items, key, row)` / `v.eachWith(ctx, items, key, row)` | keyed 列表；key 是 `.field` 或 `fn (T) u64` |
| `v.with(组件, children).trigger(children)` | 子元素放进组件 slot / trigger |
| `v.component(f, props)` | 有状态组件：`f(props, scope, cx) !*Node` |
| `v.attrs(.{ .test_id, .a11y, .on_click, .style, .state, .parts, … }, 元素)` | 给任意单节点元素（常用于组件根）补属性；`.style` 叠加在组件样式上，条件撤销回到挂载时快照（不跟随组件后续更新，见下文限制）；`.state = .{ .invalid = 源, … }` 只给这层叠加样式自己的条件（`_invalid` / `_selected` …）供源——读调用方的源，不读组件私有状态；也接受 `hover` / `active` / `focus` / `focus_visible` 钉住（同元素 `state`）；`.parts = .{ .dialog = "id", .chrome = .{ .style = S.panel, .test_id = "x" } }` 给组件内部部件（Result 的 `*Node` 字段）设 test_id 或叠属性 / 样式；`v.with(...).parts(...)` 同义 |
| `v.ref(handle, 元素)` | `handle = try v.createRef(scope, T)`；组件 T 为 `v.MountResult(Builder)`，普通元素 T 为 `*ui.Node`。`get()` 返回 `?T`，卸载或回滚清空。持有 scope 必须是挂载 scope 自身或祖先，句柄本身只在持有 scope 存活期间有效；较早挂载的 cleanup 不会清掉后来写入的句柄 |
| `v.capture(&dest, 元素)` | 同步挂载时取一次节点或组件结果，允许栈变量；目标卸载或挂载失败后捕获值无效。跨 show/each 生命周期使用 live ref |
| `v.dynamic(src, f)` | 根据源值重建动态区域；区域拥有内容的 scope，旧内容先卸载 |
| `v.list(array, f)` / `v.listWith(ctx, array, f)` | 静态数组展开成兄弟（不建区域、不建 effect）；数据会变用 `each` |
| `v.items(ctx, slice, f)` / `v.repeat(ctx, n, f)` | 运行期切片 / 次数在挂载时一次展开（不建区域）；`f` 的返回类型要写明（Zig 不能从函数体推导，写不出时包成 `v.component`） |
| `if (cond) 元素 else null` / `v.branch(cond, a, b)` | 静态条件：挂载时决定有无 / 二选一，不建锚点、不建 effect；运行期会变用 `v.show` |
| `v.image(.{ .style, .tint }, texture_id)` | 纹理图像（应用自带位图）；SVG 资源用 `v.icon` |
| `v.append(scope, cx, parent, 元素) !*Node` | 往已有节点追加单根元素，scope 绑在根上（组件「清空后重建」的循环用，不累积 scope）；`v.mount` 的 scope 随调用方 scope 释放 |
| `v.setup(元素, ctx, f)` | 逃生口：挂上后拿根节点做 DSL 覆盖不到的事（底层事件、before_render、自绘） |

**子元素**可以是：上表元素、组件 builder（有 `mount`）、`*Node` / `?*Node`、`null`、字符串字面量（默认主题文本样式）、嵌套 tuple 或数组（fragment，原地展开）。

**写辅助函数**（返回元素的函数）时返回类型要写明：把 props 存成具名常量，用 `v.Text(@TypeOf(props), []const u8)` / `v.Box(@TypeOf(props), Children, null)` 表达；需要 scope 的辅助直接写成 `fn (..., *Scope, *Cx) !*Node` 并 `return v.render(...)`。

**样式字面量**支持嵌套：`.{ .width = .{ .px = 80 }, .padding = .{ .top = 4 } }` 递归转换到 `BoxStyle`。

**props**：box / attrs 收 `style / test_id / a11y（可写字面量）/ state / on_click / on_hover / on_leave / on_focus / on_blur / visible / focusable / hit_test / tag`（box 另收 `focus_ring / on_event / event_context`；`state` 见 YIX_REFERENCE §2.10：disabled / invalid / selected / expanded 供源，hover / active / focus / focus_visible 钉住，`?bool` 的 null = 不钉），text 收 `style / test_id / a11y / visible / hit_test`，icon / image 另收 `tint`。拼错字段是编译错误，并列出可用字段。文本节点要盒样式（固定尺寸、padding、grow 宽）或事件时，用 `v.attrs(.{ .style = …, .on_click = … }, v.text(...))`。

`visible`（bool 或 bool 源）切 `display`：隐藏时子树保留（effect、列表、`v.dynamic` 照常更新），不占位、不命中、不进 a11y，也不排版。隐藏期间子树里发生的变化在重新显示后的**第一次** layout 就按终值排好（框架在显示时补排，见 `docs/BUGS.md` 2026-11-13 条目），应用侧不需要也不应再手动把整棵子树重新标脏。

**文本内容**：`v.text` 把内容拷成节点拥有的堆副本，地址在节点生命周期内稳定（a11y label / live_text 可借用）。`node.getText()` 的副本不带所有权（`owned` 恒为 false），读-改-写换成借用内容是安全的；要问「节点是否已拥有某内容」用 `getTextRaw()`。

**回调型组件**（池化 / 虚拟化，内容由组件按需索取）同样写视图函数：
`W.VirtualList(.{...}).rows(ctx, row)`、`W.Table(.{...}).cells(ctx, cell)`、`W.Grid(.{...}).cells(ctx, cell)`。
行 / 格函数 `fn (Ctx, usize) E`、`fn (Ctx, row, col) E`（ctx 传 `{}` 时省略该参数），或组件形态再加
`*Scope, *Cx` 返回 `!*Node`。每行 / 每格一个子 scope 绑在内容根上，挂在拥有该位置的 scope 下（Table：格所在行的 scope；Grid / VirtualList：组件自己的 scope），组件回收或刷新该位置、或组件本身被释放时一并销毁。

**行函数**两种形态：视图函数 `fn (T) E` / `fn (T, usize) E`（E 是单节点元素），或组件函数 `fn (T, *Scope, *Cx) !*Node`（行里要建 signal、用 `ui.on.bind` 时；函数体 `return v.render(scope, cx, ...)`）。

## 2. 样式

`.style` 是这一层的核心，把 STYLING.md 的三层模型接进声明式树：

| 写法 | 含义 |
|---|---|
| `S.card` | 具名样式函数 `fn (*const ThemeTokens) BoxStyle`，换主题重放 |
| `.{ .gap = 8 }` | 字面量 |
| `.{ S.card, S.elevated, .{ .gap = 4 } }` | 从左到右合并，后者覆盖前者（`BoxStyle.merge`） |
| `S.Card.of(.{ .selected = selected })` | 推荐：业务状态绑定 cva/sva variant；多 slot 共享同一组变体 |
| `v.when(cond, S.selected)` | 底层条件叠加，仍支持；不作为有限业务状态的推荐写法 |
| `v.hover(S.rowHover)` | 节点悬停时叠加 |
| `v.styleBy(src, S.sized)` | `fn (T, *const ThemeTokens) BoxStyle`，按源值选样式（文本则返回 TextStyle） |

**盒样式的三条执行路径，编译期决定**：

1. 样式编译期可知、且没有响应式部件（`S.card`、`.{ S.card, .{ .gap = 4 } }`）→ 挂 `on_theme` hook，与 `ui.boxStyled` 同等零成本：不建 effect；挂载时按需预分配 StyleExt，不影响 promoted 渲染缓存资格。
2. 只有运行期字面量、不读主题 → 挂载时应用一次。
3. 含响应式 `when`、`hover / styleBy`，或读主题但带运行期值 → 一个 effect 同时订阅条件源与主题 signal，重算后增量应用。

普通 `bool` 的 `when` 在挂载时确定，不因条件本身建立 effect；内部含 hover 等响应式部件时仍订阅。读主题且携带运行期值时，主题更新仍可能需要 effect。

声明式样式在挂载时检查全部条件、variant 与 compound 层，预分配可能用到的 StyleExt；样式函数 / styleBy 无法静态确定字段集合，保守预留。分配失败从挂载错误通道返回，不留到后续无错误通道的 effect 中丢字段。相同 NaN 结果按相等处理；仅颜色变化不触发布局，透明度和变换走合成失效，尺寸变化同时失效父布局。

**样式层叠**：一个节点上的所有运行期盒样式是同一个层叠的层，按层序合成目标值，再与上一次的目标值比较、只应用变化：

| 层（低 → 高） | 来源 |
|---|---|
| 元素 | 元素自己的 `style=`（配方、变体、`_hover` 等状态条件、styleBy） |
| 组件内联 | 组件对节点的命令式写入：`setBackground` / `setOpacity` / `setBorderColor` / `setTranslateX` / `node.setStyleInline(.{…})`；`node.unsetStyleInline(.{…})` 撤掉。`setStyleInline` 尽力而为（分配失败会丢掉部分写入，给 effect / 回调用）；挂载路径用 `try node.setStyleInlineFallible(alloc, .{…})`（要么完整落地、要么节点不变），多个节点要全有或全无时先逐个 `stageStyleInline` 再统一 `commit()`（失败时对已 stage 的 `abort()`；同一节点同时只能有一个未决的 stage） |
| 调用方叠加 | `v.attrs(.{ .style })`、`.parts.*.style`、模板里组件元素上的 `style=` |
| 动画 | `ui.view.loop`：独占它驱动的属性，变化立即生效、不进过渡；关掉后按过渡从当前呈现值回到作者层的值 |

所以调用方叠加始终压过组件自己的样式（包括组件的悬停效果）；某层不再声明一个属性时回落到下层（叠加撤销后是组件此刻的值，不是挂载快照），最终回到默认值。组件根被叠加时，组件自己设好的样式成为组件内联层的初值。
各层的首次应用（挂载期间）立即生效、不触发过渡；挂载时就已成立的状态（钉住的 hover / pressed、初始 disabled）同样直接落到终值。Debug 构建下，如果代码绕过层叠直接改写层叠管着的字段（`node.style.x = …`），会报出字段名与组件名——改用 `node.setStyleInline`。

**撤销语义**：条件撤销时，被它设置过、而新结果不再设置的字段回落到下层；没有任何层声明时回到 `Style` 默认值（不是停在上次的值）。border 家族（`border` 与 `border_*` 细粒度字段）只要上次碰过就整体复位后重放——否则"base 设宽度、条件设颜色"撤销后颜色会残留。background / opacity 走带过渡的 setter。

文本从主题默认值开始，字面量、css 和 recipe 文本 slot 按声明字段叠加；tuple 与底层 `when` 均支持。完整 `TextStyle` / 返回它的函数覆盖完整文本样式。文本始终依赖主题默认值，因此运行期文本字面量也跟随主题，不能套用上面的“一次性”盒样式路径。文本不接收布局字段；交互条件只有 `_hover`（文本节点自己的悬停，如链接悬停色），其余状态（`_active` / `_disabled` …）编译报错，文字业务状态使用 variant。文字的 `color` / `font_size` / `font_weight` 若没有声明，就继承最近祖先盒子上的值（布局与绘制同一份解析，见 YIX_REFERENCE §2.10「文字属性继承」）。

TextStyle 覆盖 TextProps 的全部样式字段（含 selectable、等宽 / 斜体 / 符号字体、删除线、text_overflow、fade_right）；富文本 spans 只能挂载后 setText。

BoxStyle 覆盖 StyleExt 的低频字段（同名直通：align_self、min/max 尺寸、aspect_ratio、flex_basis、outline、hit_shape、hit_behavior、overflow_fade、will_change_* 等；另有逐角圆角 `corner_radii`、多层内阴影 `inset_shadows`，以及`z_index`、`inset`、`gradient`、`multi_gradient`、`shadows`（`ui.ShadowList.of(&.{ a, b })`）、
`clip_shape`、`glass`（`ui.GlassParams`）、`composited_group`、`blend_mode`、`flex_wrap`）——都可以出现在样式函数、字面量与条件部件里，撤销时复位。

`when / hover / styleBy` 的样式参数须编译期可知（直接传函数或常量字面量）：Zig 里含函数字段的结构体只能存在于编译期，部件把样式存在类型的 decl 上、字段只存条件源，值才能在运行期保存。

悬停样式与用户 `on_hover/on_leave` 共存；多个内部 hover hook 共享事件分发，各自随 scope 注销。

## 3. 事件：`ui.on`

| 组合子 | 结果 | 分配 |
|---|---|---|
| `ui.on.set(sig, value)` | 点击时设为编译期常量 | 无 |
| `ui.on.toggle(sig)` | bool 取反 | 无 |
| `ui.on.update(sig, f)` | `sig = f(sig)` | 无 |
| `ui.on.assign(sig)` | 带值事件（on_change）写进 signal | 无 |
| `ui.on.call(state, method)` | 同 `cx.on`，不需要 cx | 无 |
| `ui.on.bind(scope, ctx, f)` | 捕获运行期值（行 id 等），ctx 拷进 scope | 一次，随 scope 释放 |

命名为 `ui.on` 而不是 `ui.act`：键盘绑定那套 Action 系统已经是 `ui.actions`。

## 4. 组件接入：`ViewParts`

`mount` 返回 `*Node` 的组件不需要任何改动。返回 Result 结构体的组件在 Result 上声明：

```zig
pub fn viewParts(self: ScrollAreaResult) core.ViewParts {
    return .{ .root = self.container, .slot = self.content };
}
```

- `root`：挂进父节点的节点；null = 组件自己挂到了别处（portal 的 Modal / Sheet）。
- `slot`：`v.with` 的子元素去处；`slot_scope`：子元素归属的 scope（Popover 内容必须随 Popover 自己的 scope）。
- `trigger`：Popover / Tooltip / Menu 的触发器插槽。

需要换挂载方式才有 slot 的组件（Card 的 `mountBody`、GlassBox 的 `mountWithState`）在 builder 上提供 `viewMount`，返回 `ViewParts` 或带 `viewParts()` 的结果结构体（后者经 `v.ref` 或同步 `v.capture` 交给调用方）。`mount` 多带参数的组件给出编译期报错；回调型组件改用 `.rows / .cells`。

已接入：ScrollArea、Card、Modal、Sheet、Popover、Group、Form、AccordionItem、Accordion、VStack、HStack、GlassBox；Tooltip、Menu（trigger，没有内容 slot）；TagsInput、Select、ComboBox、Slider、Rate、Tree、Table、DataTable、Calendar、DatePicker、DateRangePicker、NumberStepper、FileUpload、Grid、VirtualList、Input、Textarea、SnapshotLayer（仅 root）。

Yix 写的组件（ControlShell、Button、Chip、Alert…）不走 `ViewParts`：具名插槽在 Zig 里用 `v.with(W.ControlShell(.{ .variant = .field }), .{}).slots(.{ .icon = …, .content = …, .append = … })` 填，可选插槽（`?View`）不传或传 `null` 时整个槽盒不建（见 YIX_REFERENCE §2.9）。

**部件**：Result 里的 `*Node` / `?*Node` 字段都是可寻址部件，`.parts` 按字段名写 test_id 或叠属性
（Select 的 `trigger / panel / chevron_down / clear_button / search_input …`、Popover 的 `trigger / chrome / content`、
Textarea 的 `input`…）。运行期按数据生成的子项（RadioGroup 选项、Select 选项与多选标签）在数据项上带 `test_id`。

Accordion 的互斥展开在声明式树里用 `W.accordionItemOpen(open, comptime index)`：
`v.with(W.Accordion(.{ .open = section }), .{ v.with(W.AccordionItem(.{ .title = "A", .expanded = W.accordionItemOpen(section, 0) }), .{...}), ... })`。

## 5. 框架层修复（为 DSL 必须先做的）

### 5.1 控制流内容位置漂移

修复前：Show / Match 建内容一律 `appendChild`，条件后来才变真时内容跑到所有兄弟之后；For 用"段前非 For 兄弟个数"定位，前面的 Show 开合会让它漂移。父节点只放一个控制流时恰好正确（storybook 正是如此，所以一直没暴露），混排即错位。

修复：每个区域在父节点里占一对锚点 `[start, end)`（`ElementTag.anchor`：display:none、零尺寸，布局 / gap / 命中 / a11y 全部跳过），内容永远插在 end 之前。区域内容可以多节点、可以嵌套区域：清空时按位置摘掉两锚点之间的一切。配套：`Node.insertChildBefore` + `ElementTable.insertBefore`（World 兄弟链 O(1) 插入）。Show 即 bool 上的 Match，二者共用 `SwitchRegion` 内核。

### 5.2 `BoxStyle.merge` 漏字段

手写字段列表漏了 `display`，合并时被静默丢弃。改为编译期遍历全部字段（`isEmpty` 同理），测试用必须填满每个字段的 donor 守住"新增字段没跟上"。

## 6. 生命周期合同

- **事务**：元素建好立即挂进父节点（或捕获槽），失败时由事务所有者统一回收——`render` 的根、控制流区域、For 的一行。回收顺序固定：hook 失效 → dispose scope（cleanup 还能看到活节点）→ 释放节点。一次挂载出错即停，所以至多一个"建好却挂不上"的节点，它进 stray 槽，同样在 dispose 之后释放。
- **scope**：`render` 在调用方 scope 下开子 scope，整棵树的 effect 都归它；中途失败时整个子 scope 先销毁，之后再改相关 signal 不会碰已释放节点。
- **Yix 组件**：声明区使用 setup scope，编译器把整个模板求值放入 `renderComponentView` 回调，在子 view scope 中创建模板的 derive、handler 与绑定。两层 scope 不新增节点；此入口负责初次构建和失败回收，根替换协议尚未实现。手写 `v.component` 仍可在函数中显式选择声明与视图的 scope。
- **借用**：`show / match / each` 把子元素描述值按值存下，条件变化时再挂载。描述值里借用的切片（字符串、数组）必须活得比该区域久——字面量与 scope 拥有的数据天然满足，栈上拼出的字符串不满足。
- **主题 signal**：响应式样式订阅的主题 signal 是 Cx 服务（`cx.themeSignal()`），归 Cx 所有、与 Cx 同寿，不属于任何窗口或组件的 scope；换窗口根不会让其他持有者悬垂。

## 7. 验证

- `src/ui/view_tests.zig`：结构 / 三条样式路径 / when 撤销复位 / 主题跟随 / hover / 三种文本内容 / 控制流混排定位 / 嵌套区域卸载 / eachWith + on.bind / 组件协议 / 真实组件 / 失败回滚（含 effect 随子 scope 销毁）/ mount 追加回滚。
- `src/ui/on.zig`：组合子行为 + 零分配断言。
- `src/ui/control_flow.zig`：Show / Match / For 混排定位 + World 兄弟链一致性。
- storybook「View DSL」story + e2e：增删、切页、条件样式像素取样、区域位置断言。
- 植入失败验证测试确实被收集；对 border 复位与区域插入点做过变异，测试均变红。

## 8. 后续（未做）

- Yix 的未实现项见 [YIX_REFERENCE.md](YIX_REFERENCE.md) §2.13 / §6。
- 节点级 `transition` prop（setter 已支持过渡槽，缺声明入口）。
- 多后端（Web）：本层的元素树是编译期已知形状的描述值，可作为 renderer 接口的 IR；挂载过程尚未抽象成 renderer 接口。

悬停回调通过 `hooks.setHoverHandler` 注册或替换。存在 `useHover` 订阅后直接赋值 `events.on_hover/on_leave` 属于合同违例；`debug` / `safe` 在分发前检查监听链，清理不会覆盖后来直接写入的回调。

### 提升根与宿主快照（LP3）

测试 / dev-preview 的 `ComponentInstance.rebuild()` 支持刷新单根提升链中的内层实例；外层 setup / view scope 保留，外层 root、ownership binding、live ref、可重放 attrs 与宿主 RootLease 一起迁移。整个链预检通过才消费旧 view；消费后失败，整条链清空 root 并进入 needs_remount。带内部 slot / trigger 指针的外层 ViewParts 保守拒绝。没有永久根壳。

`RootLease.acquire(allocator, node)` 是显式的宿主根别名协议：返回可空 lease（非 setup/view 组件为 null），宿主读取 `lease.resolve()`，在删除宿主记录前调用 `release()`。For 行使用该协议，因此行数组搬移、重排、删除不会留下旧根。消费后失败时 resolve 为 null；scope-first teardown 后 lease 本身仍可释放，For 用 retainedNode 的 generation 校验回收仍存活的孤立根。被延迟 cleanup 取消并回收的新根不能再解析为活节点。没有 World 登记的 legacy 根保持挂载行为，但会 pin 并拒绝迁移。lease 不延长节点寿命，不可在宿主已销毁节点后解引用。

`capture` 的 Node / ViewParts 快照不能自动迁移，因此会 pin 对应组件根；手写宿主保存直接 mount 返回根或做不可重放命令式装饰时，调用 `pinComponentRoot(node)`。它拒绝该根及其提升内层的 rebuild，错误为 ViewHostRootAliasNeedsOwnerRebuild。FileUpload browse_button、窗口按钮数组及 Group 的命令式连接装饰采用此契约。原始 render / mount 返回值仍是当代快照；可重建宿主应保存 RootLease、live Ref 或实例 parts。

原生 callback 的 `renderInto` scope binding、任意结果结构的隐藏根别名，以及具有 slot / trigger 内部指针的提升宿主需要由宿主整体重挂载。不会通过复制最终节点字段推断这些引用的所有权。
