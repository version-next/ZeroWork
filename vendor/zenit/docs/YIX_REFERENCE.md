# Yix 与 YSS 语言参考

zenit 的两门声明式源语言，都编译成普通 Zig，零运行时：

| 语言 | 文件 | 写什么 | 编译成 |
|---|---|---|---|
| **Yix** | `.yix` | 组件：参数、状态、模板（类 JSX 标签）、事件 | `ui.view` 的组件与元素描述 |
| **YSS** | `.yss` | 样式配方：类 CSS 的属性块、变体、条件、mixin | `ui.css` / `ui.cva` / `ui.sva` 对象字面量 |

本文是当前 Zig 0.17.0 兼容分支的语言参考，未实现项与后续路线见 §6。
首次使用请先读 [Yix/Yss 开发指南](YIX_YSS_GUIDE.md)，Windows 构建见 [WINDOWS_BUILD.md](WINDOWS_BUILD.md)。
底层 `ui.view` 见 [VIEW_DSL.md](VIEW_DSL.md)，样式系统见 [STYLING.md](STYLING.md)，YSS 详见 [YSS.md](YSS.md)，
编辑器见 [YIX_EDITOR.md](YIX_EDITOR.md)，用 Yix 写内置组件的约定见 [YIX_COMPONENTS.md](YIX_COMPONENTS.md)。

---

## 1. 工程模型

### 1.1 双胞胎生成物

每个源文件旁边有一个**生成的双胞胎**，入库：

```
card/
  card.yix          ← 手写
  _card.yix.zig     ← 生成，勿改
  styles.yss        ← 手写
  _styles.yss.zig   ← 生成，勿改
  mod.zig           ← 手写：pub const Card = @import("_card.yix.zig").Card;
```

- 命名规则只有一条：**`_` + 源文件名 + `.zig`**。
- `.yix` / `.yss` 里引用源文件名：`const S = @import("styles.yss");`、`const C = @import("../card/card.yix");`。
  编译器生成双胞胎时把字符串换成双胞胎名（`"_styles.yss.zig"`、`"../card/_card.yix.zig"`），只认 `@import("….yix" / "….yss")`；
  注释、普通字符串、多行字符串、`@embedFile` 里的不动。编辑器里看到、跳转的都是源文件。
- 手写的 `.zig`（`mod.zig` 等）不经过编译器，仍然 import 双胞胎：`@import("_card.yix.zig")`。
- 双胞胎 = 一行文件头 + 编译器原始输出（不格式化，编辑器据此精确映射位置）+ 来源行。
- `zig fmt` 门禁跳过 `_*.yix.zig` / `_*.yss.zig`；`.gitattributes` 标 `linguist-generated`（GitHub 折叠 diff）。

### 1.2 谁来生成

| 时机 | 方式 |
|---|---|
| `zig build …`（本地） | 编译前自动重新生成过期的双胞胎（只写有变化的文件，原子写）；手改或删掉的双胞胎也会被改回来。源文件和双胞胎都没变时这一步直接跳过 |
| `zig build … --watch` | 改 `.yix` / `.yss` 即自动重新生成并重新编译 |
| 编辑器里保存 | yix-lsp 写回双胞胎（当前文本编译不过时不动；同名的手写文件不覆盖） |
| CI（有 `CI` 环境变量；仓库的 CI 另外显式跑 `check-yix`） | 只检查：双胞胎缺失、过期或被手改即失败，不改工作树 |
| 显式 | `zig build gen-yix` 重新生成；`zig build check-yix` 检查（并入 `test-headless`） |

开关 `-Dyix-gen=write|check|off` 覆盖默认（本地 `write`、CI `check`、zenit 作为依赖被构建时 `off`）。
`gen-yix` / `check-yix` 都会报告源文件已删除但生成双胞胎仍残留的情况；恢复源文件或手动移除生成物后再运行，不自动删除文件。
只读环境或 bisect 历史提交时用 `off`。`--watch` 期间新建的 `.yix` 要重启 watch 才会被监听（构建配置阶段登记输入）。

生成范围：`src/ui`、`examples`、`tests/yix`（`build.zig` 的 `yix_source_roots`）。单文件翻译：`zig build yix -- IN OUT.zig`。
依赖 zenit 的项目也可不入库、构建期翻译：`build.zig` 的 `translateYix` 返回缓存里的 `LazyPath`，或取 `zenit_dependency.artifact("yix")` 建同样的 Run step：

```zig
const run = b.addRunArtifact(zenit_dependency.artifact("yix"));
run.addFileArg(b.path("src/page.yix"));
const generated = run.addOutputFileArg("page.zig");
const page = b.createModule(.{ .root_source_file = generated, .target = target });
page.addImport("ui", ui_module);
```

这种方式下生成文件在缓存目录，引用旁边的手写文件（以及 `@import("styles.yss")`）只能改走命名 module；入库的双胞胎没有这个限制。

### 1.3 编辑器

VS Code / Cursor 插件 `editors/vscode-yix`（`zenit-yix`）+ 语言服务器 `zig build yix-lsp`：

- **高亮**：`.yix`（标签、属性、插值、Zig 部分复用 Zig 语法）与 `.yss`（关键字、属性、token、数字、颜色、条件块）。
- **Yix**：Zig 部分的悬停 / 补全 / 跳转 / 引用 / 签名 / 诊断经 ZLS（位置映射往返）；标签名补全（宿主标签 + 本文件组件）；
  属性名补全（宿主元素静态表；组件经 ZLS 查定义后解析 `<Name>Props` 字段与文档注释）；写到一半时在光标后试闭合串修补后照常补全。
- **YSS**：属性 / token（按就近的 theme.json；颜色带色块）/ 枚举值 / 条件 / `when` 的维度与选项 / 插槽 / mixin 补全；属性文档、token 明暗取值、
  配方摘要、mixin 签名悬停；mixin / 维度 / 选项 / 插槽跳转；大纲；照搬的 Zig 与 `{zig}` 值走 ZLS。
- 双胞胎在资源管理器里嵌套到源文件下、只读打开；跳转落到双胞胎时映射回源文件。
- 诊断：Yix / YSS 编译诊断 + ZLS 对生成代码的诊断 + 保存时构建的 Zig 类型错误（ZLS 不做 comptime 语义检查），都指回源文件。

详见 [YIX_EDITOR.md](YIX_EDITOR.md)。

---

## 2. Yix

### 2.1 文件结构

`.yix` 是 **Zig 的超集**：顶层除组件以外的一切（`const` / `fn` / `struct` / `test` / import）原样照搬为 Zig。
组件是返回 `View` 的函数，函数体是声明 + 一个返回模板的 `return`。推荐的组合是 `.yix` 写结构与行为、`.yss` 写样式。
下面这对文件就是 `tests/yix/doc_chip.yix` / `doc_chip.yss`，随 `zig build test-yix` 编译并运行。

```zig
// doc_chip.yix
const ui = @import("ui");
const S = @import("_doc_chip.yss.zig");     // 引用 .yss 的生成双胞胎

pub const Tone = enum { neutral, accent };

/// 可选中的胶囊；传了 onRemove 时显示移除按钮
pub fn Chip(
    label: []const u8 = "",
    tone: Tone = .neutral,
    selected: Model(bool) = false,           // 受控值：调用方传 signal 即双向绑定，不传则组件自持
    onChange: ?Handler(bool) = null,         // 选中状态落地后回调
    onRemove: ?Handler(void) = null,
) View {
    return (
        <row
            style={S.Chip.of(.{ .tone = tone, .selected = selected })}
            focusable
            focusRing
            a11y={.{ .role = .button, .label = label, .selected = selected }}
            onClick={selected = !selected}
        >
            <text style={S.label}>{label}</text>
            {if (onRemove != null)
                <row style={S.remove} a11y={.{ .role = .button, .label = "Remove" }} onClick={onRemove}>
                    <text>×</text>
                </row>
            }
        </row>
    );
}
```

```
// doc_chip.yss
const ui = @import("ui");

recipe Chip {
  base {
    direction: row;
    align-items: center;
    gap: space100;
    padding: space50 space200;
    corner-radius: full;
    background: bg-secondary;
    transition: background 120ms ease-out;
    :hover { background: bg-hover; }
  }
  variant tone = neutral {
    neutral { }
    accent  { background: mix(bg-primary, accent, 0.15); }
  }
  flag selected { border: 1 accent; }
}

style label { color: fg-primary; font-size: sm; }
style remove { padding: 0 space50; corner-radius: full; :hover { background: bg-hover; } }
```

条件可以直接写在模板里（`{if (label.len != 0) …}`），不必先定义 `has_label` 之类的 computed：模板表达式同样做静态提升。

### 2.2 组件

`[pub] fn Name(参数…) View { 声明…; return 模板; }`

| 参数写法 | 含义 |
|---|---|
| `x: T = 默认值` / `x: T` | 数据参数。组件内是 `ui.Source(T)`：调用方可传静态值或响应式源（signal / memo）。不写默认值即**必填**（Zig 编译器强制调用方传） |
| `children: View` / `header: View` | 插槽（见 2.9）：`children` 收标签里的子元素，其它名字是具名插槽。不能有默认值；模板里恰好出现一次 `{名字}`，在 `box` / `row` / `col` / `grid` 里，不能在控制流里 |
| `label: Text = ""` | 字符串参数，并且标签里的文字子元素进它（`<Button>保存</Button>` → label，见 2.4）。一个组件至多一个，不能可选 |
| `x: Model(T) = 初值` / `x: Model(T)` | 受控值（表单组件），见下。不写初值即必填（调用方必须给数据源） |
| `onX: ?Handler(T) = null` / `onX: Handler(T)` | 回调参数。`?Handler` 可选（缺省 null），`Handler` 必填 |

`Handler(T)`、`Model(T)`、`Text` 是内建类型名，写在参数类型的位置、按语法识别（不加 `ui.`；写成 `ui.Handler(…)` 会报错提示）。
组件体里的 `signal(…)` / `computed(…)` / `ref(…)` / `parts(…)` 是内建（按 token 识别，`signal (x)` 同样算），文件顶层不能再声明同名的函数或常量。

**受控值 `Model(T)`**：
- 调用方不传：组件自持，初值即默认值（非受控）。
- 调用方传 signal（模板里 `selected={sig}`）：双向绑定。
- 调用方传 `ui.split(read, write)`：读跟随 `read`，写只交给 `write` 回调，由父组件裁决是否采纳。
- 调用方传**只读**的值（computed、列表行字段 `todo.done`、组件参数）并给了 `onXChange` / `onChange`：即 React 的受控组件——
  组件显示只读值；用户操作以提议值调这个回调，父组件在回调里改数据，显示随之变化；父组件不改（拒绝）或改成别的值（改写）时，
  组件按数据源的实际值恢复 / 修正（与 `ui.split(只读值, 回调)` 同一语义，由 props 归一化自动合成，回调不会再重复调用）。
  例：`{for (todos) |todo| <W.Checkbox checked={todo.done} onChange={toggle(todo.id)} />}`、
  强制大写的输入框 `<W.Input value={shown} onChange={|v| code = upper(v)} />`。只读值而没有回调时，组件只显示、不写。
- 组件内写 `x = …` 是「提议」新值；落地后回调 `on` + 首字母大写的参数名 + `Change`（参数 `value` → `onValueChange`）。
  组件只有一个受控值时也可以用 `onChange`。回调只报落地的值。
- **视图模型持有的文字（`W.Input` / `W.Textarea` 的 `value`）**：`<W.Input value={query(vm)} onChange={|q| send(vm, m.Intent.searchFor(q))} />`
  就是受控输入框，宿主不需要 `InputResult` 句柄。约定：
  - 视图模型是唯一真相。打字以提议值调 `onChange`；视图模型在回调里**同步**写状态时，编辑原地落地（光标、选区、撤销单元不变）。
    回调里没有同步写（异步才更新），这次编辑按「拒绝」退回，之后的写入按外部写入整段替换——所以 `send` 必须同步更新 `query(vm)` 读的信号。
  - 视图模型自己改值（如导航时清空搜索词）＝外部写入：整段替换、光标到末尾、清空撤销栈、不回调 `onChange`；内容相同不动光标。
  - **输入法组合期间**的外部写入推迟：不结束组合、不丢预编辑；取消组合后应用视图模型的最新值，提交组合则用户输入优先（提交的文字照常经 `onChange` 提议，推迟的写入作废）。
  - 主题发布（`Cx.setTheme`）后文字、占位符、光标、选区、输入法高亮与标签 / 说明 / 错误文字由框架按新 token 重绘，不改缓冲、光标、选区和组合状态；使用方不需要手动重绘。
  - `InputResult.value` / `.state` 句柄 API 不变，旧写法照常可用。
- **滚动位置（`W.ScrollArea` 的 `scrollY` / `scrollX`，`Model(f32)`）**：`<W.ScrollArea scrollY={pageScroll(vm)} onScrollYChange={|y| send(vm, m.Intent.scrolled(y))}>…</W.ScrollArea>`
  让视图模型持有偏移（例如每页一个），切回页面、重新挂载时自动恢复，不需要 `ScrollState` 句柄或 after-layout 钩子。约定：
  - 写入（视图模型改值、或挂载时的初值）在下一次 before-render 里生效，并且只在滚动区已经有布局时生效——布局之前写入会等待，不会按零尺寸夹成 0；
    生效时夹到 `[0, 最大偏移]`，夹过的值回报给数据源；同时取消该轴的惯性 / 回弹，压过同一帧里的用户滚动。
  - 读取：每帧最多回报一次稳定偏移（不含橡皮筋位移），只在变化时回报，静止时不回报；只在渲染节拍里回报（主题重放、响应式计算中不回报，留到下一帧）。
    回报会写视图模型，偏移要放在独立的信号里，别让整棵树依赖它。
  - 传 signal 是双向绑定；只读源不带回调时只跟随、不回报；字面量是初始偏移。`ScrollState` / `setScrollY` 句柄 API 不变；程序化滚动（`setScrollY`、`scrollIntoView`）在下一帧回报。

- 不支持 `comptime` 参数。
- **参数名与模板属性名只收 camelCase**（`iconOnly`、`testId`；缩写按单词写，`userId` 不是 `userID`），写成 snake_case 在 `.yix` 原文位置报错并给出 camelCase 名。
  生成的 props 结构里是 snake_case 字段（组件内仍按原名用，Zig 侧写 `.icon_only`）。
- `pub fn X` 额外生成 `pub const XProps`（属性补全与外部引用用）。
- 从 Zig 使用：`X(.{ .label = "Save", .on_change = h })`，返回 `View`；可直接作为 `ui.view` 子元素，或 `.mount(scope, cx)` 挂载。
- **生命周期**：组件在调用方 scope 下创建 setup scope，声明区的 signal、Model、computed、Ref 与 effect 属于 setup；模板通过独立回调在其子 view scope 中求值，模板内的 derive、事件上下文、样式 effect 与 ref binding 属于 view。根节点仍负责最终销毁实例；本轮只实现两层资源归属，尚未开放根替换或热重建。
- 组件体只允许声明与一个 `return`；辅助函数写在文件顶层 Zig 里。同名遮蔽暂不支持；`__yix_` 前缀保留给生成代码。

### 2.3 状态

```zig
var count: u32 = signal(0);                 // 可写的响应式状态；类型必须显式写出
var msg: []const u8 = signal("hi");         // 存储按类型选：[]const u8 → 拥有型文本，其它 []const E → 拥有型列表（别名同样生效）
const double = computed(count * 2);         // 派生值（Memo），类型自动推导
```

- `signal` 必须用 `var`、写显式类型；`computed` 必须用 `const`。
- 组件局部里读响应式值必须包在 `computed(...)` 里（不允许局部快照读取）。
- **静态提升**：`computed` 与模板属性表达式只依赖参数时，运行期先求值一次，按响应式图**实际记录到的读取**决定：
  一个依赖都没有（参数此刻全是静态值、也没读外部信号）就收缩成静态值，不建 memo / effect——静态使用的组件零响应式开销；
  读到了信号（包括表达式里函数调用读到的外部 store）就保留为 memo，之后照常跟随。只有 `get()` 算读取，`peek()` 与普通全局变量不算。
  模板里的函数调用即使没有直接引用组件参数，也按调用过程中实际读取的信号跟随；返回响应式源或只能在编译期存储的值时保留原样传递。
- 不能给 `computed` 或只读参数赋值（诊断）。
**挂载句柄与生命周期**：

```zig
const field = ref();                        // 挂载句柄（默认 *ui.Node；组件元素用 ref(ui.view.MountResult)）
effect(total = price * qty);                // 读到的源变化时重跑（读取跟踪依赖）；建好即先执行一次
onMount(measure(field));                    // 根节点挂好后执行一次：此时 ref 已经有节点
onUnmount(log("bye"));                      // 组件卸载时执行
onViewAttach(measure(field));               // 本次 view 构建完成，ref 已绑定
onViewDetach(log("detach"));                // 本次 view 清理时执行
return <box ref={field}>…</box>;
```

- `ref()` 必须用 `const`；模板里 `ref={r}` 挂在元素上，挂载后 `r.get()` 取节点，卸载时清成 null。
- `effect` / `onMount` / `onUnmount` / `onViewAttach` / `onViewDetach` 的参数是事件语句（单条或 `{ a; b; }` 块），规则同 2.8；不收 `|value|`。
  effect 里的读取跟踪依赖（`.get()`），事件处理器里不跟踪（`.peek()`）。effect 归 setup scope，实例卸载时销毁。`onMount` 在首次 view 完成之后执行；`onUnmount` 在最终 setup 清理时执行。view 钩子分别归本次 view 的构建与清理；detach 在模板成功构建后才注册，清理时先于同一 view scope 中的根 ref binding 清空。构建尚未完成就失败时不执行 attach/detach。子 scope 仍先于父 scope 清理。不把 view 钩子用作外部资源的实例级初始化。
- 生成组件为 setup 保留独立实例及带类型的 render 捕获；重复构建只替换 view。测试和 `-Ddev-preview=true` 可在 UI 安全点调用 `ui.view.componentInstance(root).?.rebuild()`，用相同模板检查状态保留；普通构建调用该方法会产生编译错误。这不是 LP4 模板发布入口。
- 重建后通过实例的 `parts` 或 live ref 读取新根 / 插槽。先前返回的 `*Node`、`ViewParts` 和 `capture` 都是当次挂载快照；`capture` 可能指向栈，框架不会保留它的地址供重建写回。外部 attrs、样式、事件、parts 和 live ref 会重新绑定；slot 描述在调用方的子 scope 中重新执行，子组件状态按重新挂载处理。一次性传入的原始 Node slot、含 capture 或借用 slot marker 的 slot 描述会在重建前被拒绝，不保存其临时 context。
- 重建请求发生在回调、tick、清理、延迟释放队列、settled task 或响应式计算中时被拒绝；活动或 suspended overlay 的直接根、已被外层组件提升的根需要由宿主 / 外层实例处理。预检或 lifetime ticket 预留失败时保留旧视图；开始消费旧视图后的构建失败会清理部分新视图并返回错误，实例标为 `needs_remount`，宿主根清空，不自动恢复旧视图。`ViewMountCancelled` 可能同时销毁实例，此后不能读取借用的实例指针。成功结果会等到延迟 node cleanup 和 settled task 完成后再验证实例存活；回调销毁 setup 时清理仍存活的候选根并报告取消。调用方须处理错误；当前没有启用 LP4 的 L3 分流或错误浮层。
- 组件里不能直接用 `cx` / `scope`（编译报错）：Yix 组件是声明式的。需要挂载时命令式建状态的部分（如 `cx.bindState`），
  写成普通 Zig 组件——`fn mountX(props: P, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node` 加
  `fn X(props: anytype) ui.view.ComponentOf(mountX) { return ui.view.component(mountX, props); }`——再在模板里当标签用（见 `examples/text_input`）。
  **模板传给手写组件的属性**（`ui.view.component` / `ui.view.slotted` 按 Props 字段类型转换；入口参数写 `anytype`，写成 `props: P` 时由 Zig 自己做结构体字面量转换，前三条都不生效）：
  - 标签上的 camelCase 属性对应 Props 的 snake_case 字段（`fieldId` → `.field_id`）；Props 写成 camelCase 字段时报错并给出该用的名字。
  - 字段声明为 `ui.Source(T)`：常量属性（`action={.save}`、字面量）、`*Signal(T)` / `*Memo(T)` 与引用了组件参数 / 行变量的属性（模板传 `ui.Source(T)`）都收，组件里 `.peek()` 取挂载时的值、在 effect 里 `.get()` 跟随。
    字段声明为普通值类型 `T`：只收常量；收到响应式源时编译报错（`Props.x: the field is a plain T but receives a reactive source …`），不静默取快照。
  - 事件属性（`onChange={\|v\| …}`、`onClick={save()}`）传给 `?ui.Handler(T)` / `ui.Handler(T)` 字段（`T` 取字段的值类型，`void` 即无值）；字段不是 Handler 时编译报错。
  - 组件参数名不能是根节点保留名（`style` `parts` `testId` `visible` `a11y` 与类型化事件）与 `key`（`{for}` 行 key）：模板里这些属性落在组件根节点或列表调和上，传不进 Props。
  **模板传给原生 builder 组件的属性**（`W.Input` / `W.Textarea` / `W.Select` / `W.ComboBox` / `W.Tooltip` / `W.Slider` / `W.Popover` 等手写 Zig 组件，
  入口 `X(props: anytype)` 经 `ui.reactive.props.coerce` 转换；Yix 写的组件 `W.Button` / `W.Checkbox` / `W.Switch` / `W.Radio` / `W.Tag` / `W.Badge` / `W.Chip`
  的参数全是 `ui.Source(T)`，一律跟随）。属性按 Props 字段类型分两类：
  - **跟随源**：字段是 `ui.Source(T)` / `Model(T)`——会变的状态与文案：`disabled`、`placeholder`、`labelText`、`helper`、`errorMsg`、`invalid`、
    Select / ComboBox 的 `options`、Tooltip 的 `text`、各种受控值 `value` / `open` 等。参数、行变量、表达式、signal 原样转发，值变化后控件随之更新。
  - **挂载时取值**：字段是普通值 `T`——决定子树形状或布局度量的结构性配置：`appendText`、`width`、`size`、`inputType`、`leadingIconAsset`、
    `appendIconAsset`、`growable`、`embedded`、Select 的 `mode` / `searchable` / `panelWidth` / `maxDropdownHeight`、Tooltip 的 `position` /
    `width` / `fontSize` 等。收常量，也收参数 / 行变量 / 表达式 / signal（任何响应式源）：**在控件构建时（模板里即该元素挂载时）读一次**，
    之后源变化**不更新**（同 `testId` / `focusId` / `ui.view.atMount`）。所以行组件把参数原样转给它们可以直接写：
    `fn InputRow(unit: []const u8, hint: []const u8, off: bool) View { return <W.Input appendText={unit} placeholder={hint} disabled={off} />; }`
    ——`unit` 取挂载时的值，`hint` / `off` 跟随。要随数据变化的结构性配置，用 `{if}` / `{switch}` / `key` 让元素重新挂载。
  - 源的值类型必须就是字段类型（或可选字段的子类型）：`width={label}`（`[]const u8` 源给 `?f32`）报
    `InputProps.width: this prop is a plain ?f32 (read once when the widget is built), but got a source of []const u8 (…)`。
  - 例外：`*Signal` / `*Memo` 交给单项指针字段（`eventContext: ?*anyopaque`）仍按指针传，不取值。
  - 结构体字段写成读参数的结构字面量（`<W.ScrollArea scrollEdge={.{ .height = h }} />`）：字面量整体提升为源，挂载时取值后按字段转换成字段类型。
  - 目前仍是普通值、语义上偏状态的字段（挂载时取值，之后不跟随）：Input / Textarea 的 `readonly` / `required`，Slider 的 `labelText` / `min` / `max` / `step`，
    NumberStepper 的 `min` / `max` / `step`。需要跟随时整行重新挂载。
  - 与手写 `ui.view.component` 的区别：手写组件的 Props 由作者自己声明，普通值字段收到源是编译错误（上一条，改声明成 `ui.Source(T)`）；
    原生 builder 组件的 Props 由框架定义，结构性配置按上面的规则在挂载时取值。

### 2.4 模板与元素

模板是**单根**的标签树：`return <col>…</col>;` 或 `return ( … );`。

**宿主元素**

| 标签 | 说明 |
|---|---|
| `box` / `row` / `col` / `grid` | 容器（`row` / `col` 是方向预设的 box；`grid` 对应 `ui.view.grid`） |
| `text` | 文本：只收文字与插值；`box={…}` 给文本节点自身的盒样式（节点自己承载文字，如胶囊徽章） |
| `icon` | `<icon src={ui.icons.x} tint={…} />`：SVG 资源；`src` 可以是 prop，挂载时取值 |
| `image` | `<image src={纹理 id} />`：纹理；同样可 `tint` |
| `canvas` | 自绘：`<canvas draw={f} data={x} animate />`，`f: fn (DrawContext, Data, ui.view.Frame) !void`；数据变化重绘，`animate` 为真时每帧重绘（视口外不画）；无子项 |
| `spacer` | 弹性占位，无属性无子项 |

**宿主属性**（camelCase 写法）

| 属性 | 含义 |
|---|---|
| `style` | 视觉样式：css / cva / sva 部件、样式函数、字面量或它们的元组（见 2.10） |
| `box` | `text` 专用：文本节点自身的盒样式 |
| `testId` | e2e / DevTools 用的 test_id（可为源，挂载时取值） |
| `a11y` | 无障碍属性：字面量的字段可以是源；也可以整体是 `Source(?A11yProps)`（null = 没有语义节点），整体值是读参数或带调用的表达式（`a11y={semantics(row, on)}`）时同样提升为源、随之更新 |
| `onClick` / `onFocus` / `onBlur` / `onHover` / `onLeave` | 事件（见 2.8）。Space / Enter 在焦点节点上合成 click |
| `onFocusWithin` / `onBlurWithin` | 焦点从子树外进入 / 离开本元素的子树（含自身，DOM `focusin` / `focusout`）：子树内部移动不触发；在获得焦点节点的 `onFocus` / 失焦节点的 `onBlur` 之后运行，内层元素先；节点销毁导致的静默失焦不触发 `onBlurWithin`。容器不需要可聚焦；写在组件元素上时作用在组件根（`<W.Pressable onBlurWithin={hide(vm)}>`） |
| `visible` | bool 或 bool 源：切 display，保留子树与状态 |
| `focusable` | bool 或 bool 源：进出 Tab 序 |
| `focusRing` | 获得键盘焦点时画焦点环：`true`/`false`、`ui.FocusRingConfig`（可为信号，配置随之更新），或 `?ui.FocusRingConfig`（null 不画；有没有环在挂载时定） |
| `inert` | bool 或 bool 源：子树不可经键盘到达（Tab / Shift+Tab 与焦点域自动聚焦都跳过）、对辅助技术隐藏；不改命中（要点击穿透再写 `hitTest={false}`），显式 `setFocus` 仍可用。适合“收起但仍挂着、弹层还锚在它上面”的控件 |
| `hitTest` | `false`：不参与命中（点击穿透） |
| `tag` | 语义 tag（`.button` / `.input` …）：命中、a11y 与键盘激活按 tag 区分 |
| `onKeyDown` / `onKeyUp` / `onPointerDown` / `onPointerMove` / `onPointerUp` / `onScroll` | 类型化事件，`\|e\|` 带事件值（见 2.8）；box / row / col / grid / canvas |
| `onKeyDownCapture` / `onKeyUpCapture` | 捕获阶段的按键（见 2.8）：先于子控件收到，容器不需要可聚焦；box / row / col / grid / canvas |
| `focusId` | 焦点标识（字符串或源，挂载时取值）：运行时语义，不要用 `testId` 代替；元素本身不可聚焦时指向子树里第一个可聚焦的节点。组件元素上作用于根（见 2.8 声明式焦点） |
| `autoFocus` | 挂载后目标就绪就聚焦；之前先发生了别的焦点转移则作废。组件元素上作用于根 |
| `focusRequest` | `ui.view.FocusRequest` 源：view-model 写 `.to("id")` / `.blur()`，在本元素子树里按 `focusId` 聚焦 / 清焦点 |
| `focusRestore` | 子树重挂后把焦点放回同一 `focusId`（含文本选区）；写在不随内容重挂的容器上 |
| `motionAnchor` | 锚点名（字符串或源）：给 `anchorTo` 找目标节点，每帧读取它的窗口矩形。组件元素上作用于根（见 2.8 收向锚点） |
| `anchorCollapsed` | bool 或源：`true` 收进锚点（快照沿曲线路径缩放渐隐，结束后 display:none），`false` 从锚点展开回原位；挂载时的值是初始状态。组件元素上作用于根 |
| `anchorTo` / `anchorRect` / `anchorMotion` | `anchorCollapsed` 的目标（`motionAnchor` 名，或窗口坐标 `?ui.view.AnchorRect`）与动效 token（`ui.view.AnchorMotion` 或源；`.mode = .anchor / .fade_scale`） |
| `state` | `.{ .disabled = 源, .invalid = 源, .selected = 源, .expanded = 源 }`：样式条件的状态来源（没写取 a11y 同名字段，见 3.4）；另可钉住 `.hover` / `.active` / `.focus` / `.focus_visible`（见 2.10） |
| `ref` | 挂载句柄（见 2.3） |
| `onEvent` / `eventContext` | 底层通用事件回调与上下文（可为源；调用方挂载后改写过节点上的值就让给后写者）；不能与类型化事件同用 |
| `src` / `tint` | `icon` / `image` |
| `draw` / `data` / `animate` | `canvas` |
| `key` | 只能写在 `{for}` 行的根元素上（见 2.7） |

宿主元素只收表里的属性：写了表外的（给 `<text>` 写 `onKeyDown` 或 `focusable`、给 `<col>` 写 `columns`）在 `.yix` 原文位置报错，
拼写接近的会给出建议（`focusrng` → `focusRing`）。属性表是编译器里的单一来源（`compiler.hostAttrs`），yix-lsp 的补全用同一份，
测试会与 view.zig 的 props 列表逐项比对。

**组件元素**：`<Name … />`、`<W.Card>…</W.Card>`（带命名空间）、`<ui.widgets.Card>`。组件的属性就是它的参数；
以下名字是**根节点属性**（保留名），不进组件参数，由 attrs 包装作用在组件根：
`style` `parts` `testId` `visible` `a11y` `focusId` `autoFocus` `onFocusWithin` `onBlurWithin`、收向锚点的 `motionAnchor` `anchorCollapsed` `anchorTo` `anchorRect` `anchorMotion`，以及类型化事件 `onKeyDown` `onKeyUp` `onPointerDown` `onPointerMove` `onPointerUp` `onScroll`（见 2.8）。
组件自己也声明了这几个名字的参数时编译报错（模板里写 `<X style={…}>` 有歧义，参数也永远传不进去），组件参数要换名字。
例外：Props 自己声明了 `test_id` 的原生 builder 组件（`W.Slider` 放在轨道上，`W.DatePicker` / `W.DateRangePicker` / `W.GlassToolbar`、玻璃栏与玻璃控件放在各自的控件节点上），`testId` 交给它，落在组件指定的节点上（挂载时取值）。
例如 Button 的配方覆盖参数叫 `baseStyle`，`style` 留给根节点。其余属性（含 `onClick` / `onChange` 这类组件事件）都是组件参数，组件不声明就是未知属性。

**属性表达式的类型按属性定型**：`variant={if (on) .primary else .ghost}`、`label={if (done) "done" else "todo"}` 这类表达式，
派生值的类型取接收它的组件参数的类型（`ui.view.attrType`），所以枚举字面量、不等长的字符串字面量分支都能直接写；
拿不到参数类型时（组件函数的返回类型依赖参数）退回按表达式本身推导。

**子元素只有文字时**（`<X>文字</X>`）：组件把某个参数声明为 `Text`（内置组件都叫 `label`），文字就进那个参数（`<Button>保存</Button>`）；否则文字照常是子元素。
由 `ui.view.textChild` 按组件的声明（生成的 props 里 `pub const text_child = "label"`）在 comptime 判断，不按参数名猜，与组件名、别名无关。
手写 Zig 组件在 props 结构体里写同样的 `pub const text_child = "label";`。交给它的文字只能是静态字符串（动态文案用 `label={源}`）；同时写了属性和文字子元素会报错。

### 2.5 属性值

| 写法 | 含义 |
|---|---|
| `label="Save"` | 字符串字面量 |
| `count={expr}` | Zig 表达式；除字符串外值都要花括号 |
| `focusRing` | 布尔简写（= `{true}`） |
| `{count}` | 同名简写（= `count={count}`），只能用本地名字 |

- 表达式里引用了响应式值：单独一个名字直接把源传下去；组合表达式生成 memo（可静态提升，见 2.3）；不含响应式值的保持普通值。
  组合表达式里名字代表**值**（读取时跟踪依赖），拿不到源本身——要把源传下去就单独作为一个属性值传；`@TypeOf(n)` 这类类型位置同样是值的类型（不求值、不登记依赖）。
- 匿名结构体字面量照常写：`a11y={.{ .role = .alert, .live = live }}`。

### 2.6 文本与插值

```zig
<text>Count {count}; double {double}</text>
```

相邻的文字与 `{expr}` 合成**一个**格式化文本节点，任一源变化时重排该节点。支持 Unicode 原文。

- **格式说明符**：`{price:.2}`、`{n:>4}`，同 `std.fmt`。
- **字面花括号**：写成插值 `{"{"}` / `{"}"}`（`{{` 不是转义）。原文中的 `{` 必须闭合为插值，单独的 `}` 是错误；不配对的模板 / Zig 花括号（含文件声明区）通过正常编译诊断报告源位置，不触发 panic。
- **空白**（与 JSX 相同）：同一行内的空白原样保留；跨行时，每行去掉行首缩进与行尾空白，非空行之间用一个空格连接，空行丢弃。
  紧挨插值、但与插值不在同一行的文字之间不会自动加空格，需要时写 `{" "}`。
- **模板体注释**：子项文字段的开头（包括标签 / 插值之后），或一行缩进后的 `// …` 是 Zig 行注释，忽略到行尾；注释里的标签和花括号不解析。行尾换行仍按上面的空白规则处理。文字中间的 `//` 保留，所以 `https://example.com` 和 `说明 // 后文` 仍渲染为文字。需要以 `//` 开头的字面文字时写 `{"// 文字"}`。
- `text` 里只能放文字与插值（不能嵌标签）。
- 插值的值必须是值或直接的响应式源（参数、signal、computed）。经参数取到的**响应式字段**（`vm` 是参数、`vm.title` 是 `*Signal`）在插值里编译报错
  （`Yix {…}: the interpolated value is a reactive source …`），写 `{vm.title.get()}` 或选择器函数；此前会静默渲染 signal 的结构体转储。条件、循环、属性位置一直是编译失败。

### 2.7 控制流

控制流写在模板子项位置的花括号里，分支里是一个标签或直接嵌套的控制流。

```zig
{if (expanded) <text>Expanded</text> else if (busy) <Spinner /> else <text>Collapsed</text>}

{switch (tab) { .home => <Home />, .settings => <Settings /> }}       // 枚举，穷尽检查由 Zig 完成

{for (rows) |item| <Row title={item.title} /> else <text>Empty</text>}   // keyed 列表；else = 空列表回退
{for (rows) |item, i| <text>{i}. {item.title}</text>}                    // i 是下标源：行被复用到新位置时跟随更新
{for (options) |opt| <row key={opt.value}>…</row>}                       // 显式 key
{for (0..n) |i| <Star lit={i < score} />}                                 // 按次数展开；n 可来自参数 / 信号
{if (shown) for (rows) |item| <text>{item.title}</text>}                 // 分支里直接嵌套控制流
{if (picked) |name| <text>{name}</text> else <text>none</text>}         // 可选值捕获
{if (parsed) |v| <text>{v}</text> else |e| <text>{@errorName(e)}</text>} // 错误联合：值 / 错误捕获
{switch (shape) { .circle => |r| <text>r {r}</text>, .none => <text>-</text> }}  // 带标签联合的载荷捕获
```

- **分支惰性构造**：每个分支生成为一个函数，分支被选中时才在分支自己的 scope 里构造；分支里的派生值、事件上下文归这个 scope，
  换分支时一并释放。隐藏的分支不建它里面的 memo / effect。
- `if`：支持 else-if 链。`if (x) |v|`：`x` 是可选值或错误联合，`v` 是跟随 `x` 载荷的源——同一分支内载荷变化只更新用到 `v` 的地方，
  不重建分支；`x` 变成 null / 错误时才换到 else。错误联合的 else 可以写 `else |e|` 捕获错误。
- `switch`：支持逗号分隔的多个标签（如 `.home, .settings => <Panel />`），`=>` 前可有尾逗号；`else` 单独成分支。对枚举或带标签联合，按标签换分支，穷尽检查由 Zig 完成。联合分支 `.tag => |p|` 捕获载荷（也可写 `.a, .b => |p|`，分别按选中的标签提取载荷并检查分支类型；同样是跟随源，同一标签内载荷变化不重建）；
  `else` 分支没有载荷可捕获。
- `for (列表)`：keyed 调和（重排复用行、不重建）。循环变量 `item` 是这一行的**数据源**：同一个 key 的内容变了，不重建行，
  而是写这一行的数据源，行内用到 `item.x` 的地方跟随（**原地更新**：焦点、悬停、局部信号、进行中的过渡都保住）。
  事件里读到的是最新数据。默认 key 是 `item.id`；没有 `id` 字段或要自定义时在行根元素写 `key={…}`
  （只能引用循环变量，按内容深度哈希）。行能捕获外层的源。
- **结构先于内容**：列表的数据源、分支的条件与行 / 分支里的派生值读同一个信号时，信号变化后先做列表调和 / 换分支，
  再更新留下来的行与分支里的内容。被删除的行、被卸载的分支，其内部的派生值与 effect **不会再以新状态求值**
  ——`{for (items(vm)) |row| <text>{name(vm, row.i)}</text>}` 里 `name` 按 `vm.page` 索引，换到行更少的一页时，
  将被删的行不会拿新页配旧序号去算；`{if (pick != null) <text>{names[pick.?]}</text>}` 同理。行内派生直接读外层信号即可，
  不必把这份状态复制进行数据；写成行组件或内联在 `{for}` 里行为相同。在事件处理器里写信号（卸载被推迟到处理器返回）时同样成立。
  这条保证由 effect 的执行顺序给出：同一轮里按所属 scope 的嵌套深度先浅后深，同深度再按依赖深度（见 `reactive/graph.zig`
  `drainPendingEffects`）。
- `for (0..n)`：区间从 0 开始；`n` 静态时一次展开，会变时整体重建（行没有身份）；负数钳到 0；不能带 `else`。
- 分支里直接嵌套的 `for` 后面不能接 `else`（与外层 `if` 的 else 有歧义，诊断）；要两个分支就写两个 `{if}`。

### 2.8 事件

事件属性的值是**语句**，在事件发生时执行；整个处理器自动合批（多次写入只触发一次更新）。

| 写法 | 含义 |
|---|---|
| `onClick={count += 1}` | 信号赋值：`=` `+=` `-=` `*=` `/=`；处理器里读值是 `.peek()`（不跟踪） |
| `onClick={{ a += 1; b += 2; }}` | 多条语句：写成块（外层花括号是属性值，内层是 Zig 块）。单层花括号里只能有一条语句 |
| `onClick={if (!locked) { n += 1; if (n > 2) n = 0; } else n = -1}` | `if` / `else`（可嵌套、可带块）；语句里的 `if` 表达式必须有 `else` |
| `onClick={save()}` | 调用函数 |
| `onClick={onClose}` | 转发回调参数（可选回调为 null 时不做事） |
| `onClick={if (!disabled) onPress}` | 门控后转发 |
| `onClick={onPick(7)}` | 带一个值调用回调（必须是整条语句） |
| `onChange={\|v\| n = v}` | 捕获组件事件的值 |
| `onKeyDown={\|e\| if (e.key == .escape) { close(); e.consume(); }}` | 宿主元素的类型化事件（见下） |
| `onClick={{ const v = try parse(text); n = v; }}` | `const` 局部与 `try`：失败经 `ui.on.reportError` 上报，后面的语句不执行 |
| `<Toggle on={flag} />`（`on: Model(bool)`） | 受控绑定：组件内 `on = !on` 提议新值 |

- 调用实参支持匿名 / 具名结构体、元组和嵌套初始化器，例如 `onClick={send(vm, .{ .x = 1 })}`、`send(vm, Point{ .x = vm.x })`。初始化器字段的 `=` 不是语句赋值；字段写入或嵌套赋值仍不支持，信号赋值规则不变。
- 写入后再读拿到的是新值（`a = 1; b = a + 1` 里 `b` 用的是 1）。
- `onClick={save}` 与 `onClick={save()}` 一样，都是**调用**（不是传函数引用）。
- `onClick={ui.on.set(n, 1)}` / `ui.on.toggle(…)`：现成的处理器原样传（实参不经响应式改写，传的是源本身）。
- **组件元素上以 `on` 开头的属性按接收参数的类型分流**，不按名字猜：参数是 `Handler(T)` 才是事件；`onTop: bool` 这类数据参数按值传。
  事件语句（赋值、调用、`if`、块、`|v|`）只能给事件参数，字面量（`true`、`3`、`.x`）只能给数据参数，写反了在 Zig 编译期报错（定位回 `.yix`）；
  单个名字 / 字段（`{save}`、`{flag}`）按参数类型取一种含义。宿主元素的事件属性是固定的一张表，没有歧义。
- `if (a) x = 1; else y = 2` 不是合法 Zig（`else` 前不能有分号），报错并提示写成 `if (a) x = 1 else y = 2` 或带块的形式。
- `const` 局部只在后面的语句里可见，不能遮蔽组件里的名字；不能 `var`、`for`、`while`、`switch`。

**宿主元素的类型化事件**（`box` / `row` / `col` / `grid` / `canvas`）：

| 属性 | `\|e\|` 的类型 | 说明 |
|---|---|---|
| `onKeyDown` / `onKeyUp` | `ui.view.KeyPress` | `key` / `modifiers` / `raw_keycode` / `composing`；只发给焦点所在的元素及其祖先（无焦点时发给窗口内容根） |
| `onKeyDownCapture` / `onKeyUpCapture` | `ui.view.KeyPress` | 捕获阶段：root → 焦点元素的路径上先于目标与冒泡调用 |
| `onPointerDown` / `onPointerMove` / `onPointerUp` | `ui.view.Pointer` | `x` / `y` 是元素内坐标，`window_x` / `window_y` 窗口坐标，`button` / `modifiers`，move 带 `dx` / `dy` |
| `onScroll` | `ui.view.Scroll` | `dx` / `dy` / `phase` / `momentum` / 坐标 |

处理器默认不拦截事件：`e.consume()` 阻止默认行为（Tab 切焦点、空格 / 回车合成点击、滚动容器滚动），`e.stop()` 再停止向祖先传播。
事件沿父链冒泡，子元素上发生的事件祖先也会收到。这几个属性与底层的 `onEvent` 不能用在同一个元素上。

**组件元素上的类型化事件**（`<W.Input onKeyDown={…} />`）：挂在组件根的捕获槽，先于组件自己的处理——焦点在组件根或它内部时都先到这里；
`e.consume()` / `e.stop()` 让这个事件到此为止：组件不再处理（例如拦下 Input 对某个键的默认处理），组件外层的祖先也不再收到；
不调用则组件照常处理。焦点、点击合成不受影响（按命中决定，不看处理器的返回）。
不占用组件根自己的 `onEvent`；组件根已经有捕获处理器时挂载失败。

**捕获阶段按键**（`onKeyDownCapture` / `onKeyUpCapture`，只用于宿主元素）：写在元素的捕获槽，按键路径经过这个元素就先到这里，
之后才是焦点元素自己的 `onKeyDown` 和冒泡。焦点在子树内时会经过；窗口没有焦点时，按键发给窗口的内容根，
所以整窗快捷键写在窗口模板的根元素上。**容器不需要 `focusable`。** `e.stop()` 让目标和冒泡阶段都收不到这个键
（整窗快捷键用它），`e.consume()` 只阻止默认行为，目标仍会收到。捕获处理器所在元素本身就是焦点元素时，
`consume` 也会跳过它自己的 `onKeyDown`。焦点所在的输入框正在组字（`e.composing`）时，按键归输入法，
捕获处理器不会被调用。分层的 Escape 建议写在冒泡阶段（根元素的 `onKeyDown`）：内层控件先处理并 `stop()`，
没人要时才到窗口。设计说明见 `docs/FOCUS_AND_KEY_CAPTURE_DESIGN.md`。

**声明式焦点**（`focusId` / `autoFocus` / `focusRequest` / `focusRestore`）：焦点目标用 `focusId` 命名（运行时语义，与 `testId` 分开），
框架在目标**就绪**（挂在窗口树上、显示、可聚焦或子树里有可聚焦节点、未禁用、不在活动陷阱作用域之外）后执行，
未就绪就挂起到下一帧开头再试（`Cx.settlePendingFocus`，`Cx.render` 自动调用）。规则只有一条：**后写者赢**——
登记之后发生的任何焦点转移（点击、Tab、`cx.setFocus`、另一个声明式聚焦）都会作废更早的挂起项。

```yix
<box testId="settings.window" focusRequest={vm.focus}>          // vm.focus: *Signal(ui.view.FocusRequest)
    <W.Input focusId="settings.search" autoFocus />              // 打开时的初始焦点
    <box focusRestore> {switch vm.page} … {/switch} </box>     // 换页重挂后回到同一 focusId
</box>
```

view-model 里 `vm.focus.set(vm.focus.peek().to("settings.search"))` 发起聚焦（目标已在树上时立即生效），
`.blur()` 清掉本元素子树里的焦点；挂载时源里的值只作基线，不会重放。`focusRestore` 只在焦点因子树销毁而**被动**丢失时生效
（主动 blur 不算），恢复时沿用丢失前的焦点环可见性，并在目标是文本输入（`set_selection`）时恢复选区。

**收向锚点 / 从锚点展开**（`motionAnchor` / `anchorCollapsed` / `anchorTo` / `anchorRect` / `anchorMotion`）：
浮动卡片切到别的 tab 时收进所属 tab、切回时展开这类过渡（类似 macOS Dock 最小化，第一级：曲线路径 + 缩放 + 渐隐）。

```yix
<box motionAnchor={tabAnchor(vm, row)}> … </box>                    // 锚点：tab 条里的一个 tab
<box anchorCollapsed={!isCurrentTab(vm, card)} anchorTo={ownerAnchor(vm, card)}>   // 卡片
    …
</box>
```

`anchorCollapsed` 变成 `true` 时，元素上一帧的画面被快照，沿曲线收进锚点并渐隐，结束后 `display: none`
（不占布局、不画、不命中、不在 Tab 序里）；变回 `false` 时重新布局、下一帧重新快照（收起期间内容变了也按现在的样子展开），
从锚点展开回原位。中途改值从当前状态反向，不排队；动画期间元素不接收命中；结束后不留快照。锚点每帧重新读取，
tab 条滚动时跟着走，滚出裁剪区时取裁剪区里最近的一端；锚点取不到时用最后一次的矩形，从未取到则退化为原地淡入淡出。
系统“减少动态效果”开启时原地淡入淡出（`anchorMotion` 的 `.reduced = .instant` 改为直接显隐）。
`anchorMotion` 的 `.mode = .fade_scale`（预设 `ui.fx.anchor_transition.fade_scale_tokens`）改为原地淡出并轻微缩小到约 0.97、展开时反向，不飞向锚点；
`anchorMotion` 可以是源，静止时改值立即生效，过程中改值从下一次过程生效。
过渡接管元素的显示状态，不要同时写 `visible`。Zig API 与设计说明见 `docs/ANCHOR_TRANSITION.md`。

未实现：字段写入、表达式内新建绑定。

### 2.9 子元素插槽

```zig
pub fn Panel(title: []const u8 = "", children: View) View {
    return <col><text>{title}</text><col>{children}</col></col>;
}
// 使用：<Panel title="Settings"><text>value {n}</text><Button onClick={n += 1}>More</Button></Panel>

pub fn Frame(header: View, children: View, footer: View) View {
    return (
        <col>
            <row>{header}<text>…</text></row>
            <col>{children}<text>always last</text></col>
            {footer}
        </col>
    );
}
// 使用：<Frame header={<text>Title</text>} footer={<Button onClick={save()}>Save</Button>}><text>body</text></Frame>
// Zig：ui.view.with(Frame(.{}), .{ body }).slots(.{ .header = …, .footer = … })
```

- 标签里的子元素进 `children`；组件元素上**值是元素**的属性（`header={<…/>}`，只能是一个元素）进同名的具名插槽。
- `{名字}` 可以在容器的任意位置：在末尾时子元素追加到容器末尾；在中间时那里放一个锚点（不占位、不计 gap、不进命中与 a11y），子元素插在它前面。
- 插槽里的内容归**调用方**的 scope（读写调用方的信号），挂在组件提供的位置上。最多 4 个具名插槽。
- **可选具名插槽**（`icon: ?View`）：调用方没传时，组件里包着它的那个元素整个不建（不占位、不计 gap）。
  模板里只能这样写：`{if (icon) <box style={…}>{icon}</box>}`——`if` 的条件就是插槽名，只带一个元素、不带 `else`，元素里必须有 `{icon}`。
  ```zig
  pub fn Field(icon: ?View, children: View, append: ?View) View {
      return (
          <row style={S.root}>
              {if (icon) <box style={S.icon}>{icon}</box>}
              <row style={S.content}>{children}</row>
              {if (append) <box style={S.append}>{append}</box>}
          </row>
      );
  }
  // <Field icon={<icon src={…} />}>…</Field>：只建 icon 与 content 两个槽盒
  ```
  - 是否传入在挂载前判定、此后不变（插槽是结构，不是状态）：Yix 调用方写了 `icon={<…/>}` 即传入；
    Zig 调用方 `.slots(.{ .icon = null })` 或值为 null 的可选元素算缺席。要随数据出现 / 消失的内容，放进插槽内容自己的 `{if}`。
  - 可选插槽不能放进响应式控制流（与普通插槽一样），`children` 不能是可选的。
  - 生成的组件函数多一个参数 `ui.view.SlotPresence`（本次挂载实际传入了哪些具名插槽）；手写 Zig 组件同样可以用
    `ui.view.slotted(f, props)` 配 `fn f(Props, ui.view.SlotPresence, *Scope, *Cx) !ViewParts`。
- 只挂一个节点的组件（`ui.view.component`，或没有声明 `children: View` 的 Yix 组件，如 `W.Button`）没有插槽：
  `<W.Button>…元素…</W.Button>` 在 Zig 编译期报 `… mounts a single node and has no children slot`（此前到挂载时才是 `error.ViewComponentHasNoSlot`）；
  按钮的内容走参数（`label` / `iconAsset`）。内容由调用方决定的整行按钮（图标 + 标题 + 副标题 + 尾部箭头）用 `W.Pressable`：
  无默认外观的按钮语义根，子元素即内容，`testId` / `style` 落在可点击的根上：
  ```zig
  <W.Pressable testId={rowId} a11yLabel={title} selected={on} disabled={locked} onClick={pick(id)} style={S.Row.of(.{ .selected = on })}>
      <icon src={glyph} style={S.row_icon} />
      <col style={S.row_copy}><text style={S.title}>{title}</text><text style={S.subtitle}>{subtitle}</text></col>
      <icon src={ui.icons.chevron_right} style={S.row_chevron} />
  </W.Pressable>
  ```
  `look={…}`（`ConditionalStyle`）按根自己的 `disabled` / `selected` / `expanded` 与悬停 / 按下逐层解析；元素上的 `style` 是叠加层，
  它的 `:selected` / `:disabled` 条件读不到组件的参数，选中态写成配方变体（如上）。
- **带触发器的弹出组件**（Zig 里 `ui.view.with(…).trigger(…)`）在模板里这样写：
  ```zig
  // Tooltip / Menu：子元素就是触发器（它们没有别的内容插槽：提示是 text，菜单行来自 items）
  <W.Tooltip text={tip} openDelayMs={450} parts={.{ .content = "help.content" }}>
      <W.Button testId="help" iconAsset={ui.icons.circle_question_mark} iconOnly={true} a11yLabel="帮助" />
  </W.Tooltip>
  // Popover：子元素是浮层内容，触发器写成具名插槽 trigger={…}
  <W.Popover trigger={<W.Button label="Info" />}><text>details</text></W.Popover>
  ```
  触发器内容归调用方的 scope（同 `.trigger(…)`）；`trigger={<…/>}` 在组件没有同名具名插槽、但有触发点时（Popover / Tooltip / Menu）
  填进触发点。`parts={.{ .content = id }}` 给 Tooltip 的提示面板写 test_id（`TooltipResult.content`；`parts` 认的是挂载结果上的
  `*Node` 字段，不限于 `viewParts`）。`testId` / `style` 落在组件根（包住触发器的 wrapper）上，不在触发器上——要给按钮写 id，写在按钮上。
  Select / ComboBox / DatePicker 的触发器是组件内部的 ControlShell，不收调用方元素（外观走它们的 props，如 `panelStyle`）；
  `select_headless` 的 `render_trigger` / `render_item` 是 Zig 渲染回调，没有模板形态。
- 未实现：片段（组件返回多个根），见 §6。

### 2.10 样式接入

`style={…}` 收下列任意一种，或它们的元组 `.{ a, b }`（后者覆盖前者）：

| 写法 | 说明 |
|---|---|
| `S.title` | `ui.css(...)` 样式对象（YSS 的 `style`） |
| `S.Card.of(.{ .kind = v, .selected = sel })` | `ui.cva` 配方（YSS 的 `recipe`），维度值可以是源。维度值也可以是表达式：行变量的字段（`{for (xs) \|x\| <box style={S.R.of(.{ .on = x.on })} />}`）、对参数的运算或带参调用（`.{ .locked = locked(vm), .on = !off }`），按普通属性值的规则提升（只读参数 / 行变量时派生，读组件信号时 memo，调用先探测实际读取）；单个名字和字面量照旧原样传，由视图自己读源。`S.name.of(…)` 参数化样式同理（只认 `.of(.{ … })`；`.slot(…)` 与 `parts(…)` 的参数仍按名字原样传） |
| `S.Tone.of(.{ .kind = v }).merge(layers)` | 配方 + 运行期分状态层（`ConditionalStyle` 或它的源、`ui.view.Look` 或它的源，或它们的元组按序并入）：逐状态并进配方（base 并 base、hover 并 hover……）后再按节点状态解析——调用方的 base 在配方的 `:hover` / `:active` / `:disabled` 之下（元组里靠后的部件则压过前面部件的一切状态）。层里可以出现任何条件，所以元素要给齐四个语义状态源（`state=` 或 a11y） |
| `S.Tag.slot(.root, .{ … })` | `ui.sva` 插槽配方的某个插槽 |
| `p.root`（`const p = parts(S.Tag, .{ … });`） | 插槽配方一次解析：一组维度值驱动全部插槽，漏传维度编译报错（组件体里声明） |
| `S.name.of(.{ .p = 源 })` | YSS 参数化样式（尺寸、间距、颜色覆盖等随参数变化的值，见 YSS.md） |
| `ui.view.styleBy(源, f)` | 逃生口：`f(值, tokens) BoxStyle`，只有 Zig 才算得出来的样式。用在 `<text>` 上时 `f` 返回整份 `TextStyle`（含颜色），或一个只含部分字段的结构体（如 `struct { font_size: f32, line_height: f32 }`）——只叠这些字段，没写颜色就照常继承祖先的文字颜色 |
| `ui.view.statesBy(源, f)` | 运行期才知道的条件层：`f` 返回 ConditionalStyle，悬停 / 按下由节点状态叠加 |
| `ui.view.loop(.{ .period_ms, .on }, f)` | 随时间循环：样式 = f(相位, tokens)，墙钟相位，视口外不推进 |
| `.{ .gap = .space200 }` | 内联字面量 |

- **控件的分状态外观 `look`**（`W.Button`，以及 ControlShell 的 `rootLook`）：值是 YSS `style`（可带 `:hover` / `:active` /
  `:disabled` 等条件块、token 颜色、token 渐变）、配方 / 插槽配方 / 参数化样式部件（`S.R.of(.{ .on = x.on })`，维度可以是源或表达式），
  或它们的元组。它按状态并进控件的色调（base 并 base、hover 并 hover……，与 `baseStyle` / `hoverStyle` / `pressedStyle` 同一套规则，
  排在它们之后），每次重算样式时按当前主题解析，所以主题切换自动跟随。和元素上的 `style`（叠加层，压过色调的一切状态，含 `:disabled`）
  不同，色调的 `:disabled` 仍在 look 的 base 之上——除非 look 自己写了 `:disabled`。注意渐变：色调的 `:disabled` 只换 background，
  look 的 base 渐变仍会画出来，禁用时要换渐变就在 look 里写 `:disabled { gradient: … }`。
  ```
  style save_fill {
    gradient: button-primary-bg accent diagonal;
    :hover { gradient: bg-hover accent diagonal; }
    :disabled { gradient: disabled-bg disabled-bg diagonal; }
  }
  ```
  `<W.Button label="保存" variant={.primary} disabled={off} look={S.save_fill} />`。值的类型是 `ui.view.Look`（类型擦除的样式部件，
  最多 64 字节的维度源）；Zig 里 `W.Button(.{ .look = S.save_fill })`（props 转换）或 `ui.view.Look.from(S.save_fill)`。
  不收 `transition`（编译期报错，过渡写在元素的 `style` 上）、不收 `ConditionalStyle` 值（太大；具体颜色仍走 `baseStyle` / `hoverStyle` /
  `pressedStyle`）。模板里 `look={…}` 写名字或一次 `X.of(.{ … })` 调用（按 `style` 的规则原样传、维度提升）；`if` 选两个部件之类的表达式不支持，
  改写成带维度的配方。
- 组件用 `parts={…}` 给内部部件传样式或 test_id：值是字符串即 test_id，也可以是字符串源（组件参数、信号：`parts={.{ .input_container = fieldId }}`），挂载时取值（同 `testId`）；
  也可以直接给样式 / 配方 / 它们的元组（`parts={.{ .content = S.Content.of(.{ .overview = overview(vm) }) }}`，同 `.style`）；
  或者写成属性结构 `.{ .test_id = …, .style = … }`。这些值和元素上的同名属性一样处理：`.style`（及直接给的样式）按 `style` 的规则，
  配方维度值是表达式时提升（`.{ .on = flag(vm) }` 读 view-model，源变化后部件随之重算样式）；test_id（直接给的值或 `.test_id`）、
  `.visible` 是表达式（`idOf(vm)`、`!off`）时按普通属性值提升，test_id 仍只在挂载时取值一次。单个名字和字面量照旧原样传。
  和 `style` 一样，样式位置上的整段调用（`.style = .{ S.pill, radius(vm) }` 里的 `radius(vm)`）不提升，函数收到的是源；
  随数据变化的样式写成带维度的配方。类型不对时编译报错（如 `ui.view .test_id: expected a string or a source of []const u8`）。
- `state={.{ … }}` / `a11y={.{ … }}` 的字段值同理：是表达式（`.selected = !off`、`.label = label(vm)`）时按普通属性值提升，字段变成源，
  视图随源更新；`ui.view.atMount(源)` 是有意的挂载期读取，原样传。
  `a11y` 的整体值（不是结构字面量）是表达式时也提升：`<W.Switch checked={on} a11y={switchA11y(row, on)} />` 得到 `Source(?A11yProps)`，
  随源更新，不必先 `computed` 中转（单个名字、`null` 照旧原样传；`state` 的整体值不提升，写结构字面量）。
- token 引用在应用时取值，换主题自动重放；静态样式不建 effect（挂节点的主题重放槽）。
- 过渡：样式对象里 `.transition = ui.transition("background 150ms ease-out")`（YSS 里直接写 `transition: …;`）。
- 条件的状态来源（普通宿主元素上）：
  - `_hover`（YSS `:hover`）、`_active`（`:active`，按下且指针仍在节点内）、`_focus`（`:focus`）、`_focus_visible`（`:focus-visible`，
    键盘等非点击方式获得的焦点）由节点自己驱动；
  - `_disabled` / `_invalid` / `_selected` / `_expanded` 取元素的 `state={.{ .disabled = 源, … }}`，没写就取 `a11y` 的同名字段；
    样式用了某个条件、两处都没有时编译报错；
  - 只为配方实际用到的条件接线；状态只看节点自己，不向后代传播。业务状态（选中项、种类）仍推荐写成 cva / sva 的变体。
  - **钉住节点驱动的条件**：`state={.{ .hover = true }}`（`.active` / `.focus` / `.focus_visible` 同理）让该条件恒为开，`false` 恒为关，
    不写则照常由节点驱动；值可以是信号。用于设计稿样本、文档与测试（相当于 DevTools 的 :hov），`disabled` 仍短路一切。
    挂载时的首次应用不走过渡（静止态截图确定）。`state` 只接受 disabled / invalid / selected / expanded / hover / active / focus / focus_visible，写错名字编译报错。
  - **组件转发钉住**：组件参数声明为 `pins: ui.view.Pins = .{}`（四个 `?bool` 字段，null = 不钉），根元素上写
    `state={.{ .hover = ui.view.atMount(pins).hover, .active = ui.view.atMount(pins).active, … }}`——`?bool` 为 null 时该条件照常由节点驱动。
    `ui.view.atMount(x)` 对普通值原样返回、对响应式源只在挂载时 `peek` 一次（不登记依赖），所以经 `Pins` 转发的钉住在挂载时定型，
    之后改源不生效；要随数据切换钉住，直接把 bool 源写进宿主元素的 `state`。ControlShell 的 `pins` 参数即此写法
    （`src/ui/components/control_shell/control_shell.yix`，Controls story 用它展示悬停 / 按下态）。
  - 手写 Zig 的 `ui.view.attrs(.{ .style = 叠加层, .state = .{ .invalid = 源 } }, 组件)`：`state` 只给**调用方叠加层自己的**条件供源
    （读调用方的源，不读组件私有状态），同样可以钉住 hover / active / focus / focus_visible（只作用于这一层）。Yix 模板里组件元素上的
    `state=` 不是根属性，是组件参数。
- 条件层的优先级是固定的：**base ← selected ← expanded ← hover ← active ← focus ← focus-visible ← invalid**，`disabled` 短路其余一切；
  与书写顺序无关。
- 文本：唯一的条件是 `:hover`（文本节点自己的悬停）；用在 `<text>` 上的 css 样式可以同时写盒属性（落到文本节点自身，同 `box=`），
  不能放进元组，`v.when` 里只能切换文字字段。
- 依赖数据的样式用参数化样式（`S.name.of`）或 cva / sva 的变体，`styleBy` 是逃生口；每个节点只能有一个 `ui.view.loop`。
- 图标着色：随样式变体 / 条件走写 YSS 的 `icon-color`；跟随任意数据写 `tint={ui.view.tintBy(源, f)}`。元素自己的样式与 `tint=`
  不能同时给（编译报错）；运行期层（cva `.merge(layers)`、调用方 `v.attrs` 叠加）里的 `icon_color` 叠在元素着色之上：层声明期间用层色，
  撤销后恢复元素的整个着色模式（含当前色）。
  `tintBy` 的 `f` 可以返回 `?Color`：`null` = 当前色（CSS `currentColor`：最近的祖先文字颜色，绘制时取值；没有祖先声明时用 fg-primary）。
- 文字属性继承：盒子上的 `color` / `font-size` / `font-weight` 由后代继承，文字自己声明的优先（css / 样式字面量 / 部分结构体只算写了的
  字段，整份 `TextStyle` 三项都算声明）。字号与字重的继承同时作用于布局测量和绘制（同一份解析，`Node.resolveTextProps`）；当前色图标与
  canvas（`DrawContext.current_color`）跟随颜色。祖先的这几个值变化（悬停、禁用、换主题）时，读它们的后代自动重新测量 / 重画——控件的
  前景色与字重写在控件根上即可，标签、图标、自绘随状态一起变，不必各自接状态。

### 2.11 编译期诊断（节选）

花括号 / 分隔符不配对时报 `unterminated Zig expression`、`unbalanced Zig expression` 或 `unmatched '}' in template body`，同样携带源位置。

诊断指向 `.yix` 的源位置（CLI 打印 `路径:行:列: error: …`，编辑器里实时显示）：

- 结构：`a View component returns one root tag`；`closing tag does not match opening tag`；`unknown host tag …`；
  `text accepts text and interpolation only`；`spacer takes no attributes or children`。
- 状态：`signal declarations require an explicit value type`；`signal declarations must use var`；
  `computed declarations must use const`；`reactive reads in component locals require computed(...)`；
  `cannot assign to a computed value or read-only prop`。
- 参数：`component parameters require a type`；`a component parameter cannot be named \`key\`` （以及 `ref` 与根节点保留名 `style` `parts` `testId` `visible` `a11y`、类型化事件：在组件元素上它们另有含义，参数永远收不到）；`only one parameter can be Text`；`component parameter names are camelCase: write …`；
  `write the built-in parameter type as Handler(T) (without ui.)`；`a Model parameter cannot be optional`；`the only View parameter is children`。
- 属性：`attribute names are camelCase: write …`；`<tag> has no attribute …`；`label is given both as an attribute and as text children`。
- 组件体：`` `cx` / `scope` is not available in a Yix component …``。
- 插槽：`component declares header: View but the template has no {header}`；`{children} appears more than once`；`{children} (a slot) cannot be inside control flow`；
  `{icon} is an optional slot (?View); place it inside {if (icon) …}`；`{if (icon) …} must contain {icon}`；`… takes no else`；`children cannot be optional`；
  `element values only go on component attributes (named slots)`；`the value of … must be a single element`。
- 列表：`a row key may only use the loop variable`；`key={…} only goes on the root element of a {for} row`；
  `loop ranges start at 0`；`for (0..n) takes no else branch`。
- 事件：`events support function calls, simple signal assignments and if / else`；`an if expression in an event statement needs an else`；
  `a callback takes at most one value`；`events on host elements carry no value; |v| works on component events`；
  `several event statements go in a block: onClick={{ a; b; }}`；`` `; else` is not valid Zig …``。
- 元素：`canvas requires draw=…`；`icon / image require src=…`；`icon / image take no children`。
- 控制流：`else |err| needs if (x) |v| on an error union`；`the else branch of a switch has no payload to capture`。
- 尚未实现的写法：`shadowed local names are not supported yet`；
  `comptime component parameters are not implemented`；`expression-local bindings and captures are not implemented`。

Zig 层面的类型错误（属性名拼错、类型不符等）由 `zig build` 报出，指向双胞胎或接收属性的库代码（如 `props.zig`）。换算回源文件：

- 命令行：`zig build 2>&1 | zig-out/bin/yix map-errors`——双胞胎里的位置换成 `.yix` / `.yss` 的行列（原位置留在行尾）；
  位置在库代码里的错误，按引用链里的组件体帧（调用方写模板的地方）补一行 `.yix` 位置的 note。
- 编辑器：yix-lsp 保存时在工作区根目录跑构建，同样换算后作为 `zig build` 来源的诊断显示在 `.yix` / `.yss` 上（见 [YIX_EDITOR.md](YIX_EDITOR.md)）。

双胞胎里模板一个元素一行、按嵌套缩进，派生值单独成块，所以报错行能对应到源里的一个元素或一个表达式。

### 2.12 成本模型

Yix 生成的是普通 Zig，但有几处分配与运行期工作在源码里看不见，列在这里：

| 写法 | 运行期成本 |
|---|---|
| `var x: T = signal(v)` | 一个 signal（组件 scope 分配，组件卸载时释放） |
| `computed(…)` / 模板里依赖响应式源的表达式 | 依赖此刻全是静态值时直接求值、**不建 memo**；否则一个 memo（首帧多一次求值，用来判定静态与否） |
| 事件属性（`onClick={…}`） | 一个处理器：捕获的名字拷进 scope 里的上下文（一次分配） |
| `effect(…)` | 一个 effect（建好先执行一次） |
| `{if …}` / `{switch …}` 的分支 | 分支惰性构造：选中时在分支自己的子 scope 里建，切走时整块释放；源静态时没有分支开销 |
| `{for …}` 的每一行 | 一个子 scope；按 key 调和，同 key 的行原地更新 |
| `style={…}` 里有响应式部件 / 参数化样式的参数是源 | 一个 effect 重算并增量应用；全部静态时只随主题重放、不建 effect |
| `ui.view.loop` | 开着时每帧按相位重算（视口外不推进） |

没有隐藏的控制流：事件里的 `try` 失败经 `ui.on.reportError` 上报（不中断别的处理器），其余错误照常经 `try` 冒到挂载调用方。

### 2.13 已知限制

- 单根：组件只能返回一个根节点（没有片段）。
- 未实现：片段（多根）、局部组件、render prop、comptime 参数、事件字段写入、
  按子项位置出样式（`:first-child` 类）、canvas 的命中形状由绘制给出。
- **数据的判等与所有权**：
  - `Signal.set` 按**内容**判等（切片逐元素、字符串逐字节、结构体逐字段）：内容相同的新数组不会通知，换了地址但内容不变的借用字符串也不会。
    列表的 key 命中后同样按内容判断这一行要不要更新。
  - 谁持有字符串：Yix 里声明的 `var msg: []const u8 = signal(…)` 与 `var xs: []const T = signal(…)` 是**拥有型**（写入时复制，调用方的缓冲可以随即释放）；
    `[]const u8` 参数、经 `scope.createSignal` 建的信号、列表里每一项的字符串字段是**借用**的切片，调用方要保证它比读它的节点活得久。
  - 推荐：列表数据放在拥有型列表信号或长期存在的数组里（例如 store 持有的 `std.ArrayList`），换数据时整体 `set` 新的切片；
    不要原地改写数组元素后再 `set` 同一个切片（内容判等看到的已经是新内容，旧值没有留存，比较结果是「没变」）。

---

## 3. YSS

### 3.1 文件结构

`.yss` 顶层的 `recipe` / `style` / `mixin` 是样式 DSL，其余照搬为 Zig（import、依赖数据的样式函数）。文件里要有
`const ui = @import(...)`（生成代码引用 `ui.cva` 等）。组件的样式文件约定叫 `styles.yss`。

```
const ui = @import("../../ui.zig");

/// 卡片根：选中时 2px accent 边框且不显示悬停高亮
recipe Card {
  base {
    direction: column;
    background: bg-primary;
    corner-radius: 6;
    transition: background 120ms ease-out, border-color 120ms ease-out;
  }
  variant kind = default {
    default  { border: 1 border; }
    outlined { border: 1 border-strong; }
    elevated { shadow: md; }
  }
  flag selected { border: 2 accent; }
  flag hoverable;
  when hoverable & !selected & kind in (default, elevated) {
    :hover { background: bg-hover; }
  }
}

mixin tone(fg) {
  root { background: mix(bg-primary, fg, 0.25); }
  label { color: fg; }
}

recipe Tag slots(root, label) {
  base { root { gap: 4; } label { font-size: sm; } }
  variant color = neutral {
    neutral { label { color: fg-primary; } }
    accent  { tone(accent); }
  }
}

style title { color: fg-primary; font-size: 14; font-weight: 600; }

/// 依赖参数的值：参数化样式（视图里 S.size.of(.{ .width = width, .height = height })）
style size($width: ?f32, $height: ?f32) { width: $width ?? fit; height: $height ?? fit; }
```

### 3.2 声明

| 写法 | 生成 |
|---|---|
| `style name { … }` | `pub const name = ui.css(.{ … });` |
| `recipe Name { … }` | `pub const Name = ui.cva(.{ … });` |
| `recipe Name slots(a, b) { … }` | `pub const Name = ui.sva(.{ .slots = .{ .a, .b }, … });`，各块里按插槽分 `a { … }` |
| `mixin name(p, q) { … }` | 不生成代码；`name(x, y);` 在调用处展开，参数按名字替换（声明顺序不限，禁止递归） |

声明前的 `///` 文档注释保留到生成代码（mixin 的随之去掉）。`pub` 前缀可写可不写（配方本来就生成 `pub const`）。

### 3.3 配方的段

| 段 | 含义 |
|---|---|
| `base { … }` | 始终应用 |
| `variant dim = 默认 { opt { … } … }` | 变体维度；不写默认取第一个选项。维度名不能与关键字（base / variant / flag / when / in）同名，按含义起名（`variant kind`） |
| `flag dim { … }` / `flag dim { … } else { … }` / `flag dim;` / `flag dim = true { … }` | 布尔维度：块是开着时的样式，`else` 块是关着时的样式（不写为空）；`flag dim;` 只用于复合条件。单个 flag 的两态用 `else`，多个维度组合用 `when` |
| `when 条件 { … }` | 复合规则；条件 `a & !b & c = x & d in (y, z)`，`in` 展开成多条规则 |

合并顺序：base < variants（多个维度按声明顺序，flag 的 `else` 块在它自己的位置）< when（与 `ui.cva` 一致）。

**命名**：配方 PascalCase（生成的是类型）；样式、插槽、维度 snake_case（`close_icon`），不加 `Style` 后缀——编译器检查。
维度按含义起名：组件参数叫 `variant` 时维度叫 `kind`（`variant variant` 读起来像语法错误，编译器拒绝）。

**两种 `when`**：配方的 `when a & !b & c = x` 引用的是**维度**（不带 `$`），展开成 cva 复合规则，按条件匹配后叠加；
参数化样式的 `when $flag & $e = x & {zig}` 引用的是**参数**（带 `$`），可以写 `{zig}` 条件，按书写顺序叠在 base 上。

### 3.4 块的内容

- `属性: 值;`
- 条件块：`:hover` `:active` `:focus` `:focus-visible` `:selected` `:expanded` `:invalid` `:disabled`（插槽配方里写在插槽块内）。
  用在**普通元素**上时的状态来源：`:hover` / `:active` / `:focus` / `:focus-visible` 由节点自己驱动（`:focus-visible` 是键盘等非点击方式获得的焦点）；
  `:disabled` / `:invalid` / `:selected` / `:expanded` 取元素的 `state={.{ .disabled = 源 }}`，没写就取 `a11y` 的同名字段，
  两处都没有时编译报错。状态只看节点自己，不向后代传播；只为配方实际用到的条件接线。
- mixin 调用：`tone(accent);`
- 插槽块（插槽配方的 base / 选项 / when 第一层）：`root { … }`。
- 同一块里**属性**后写覆盖先写（mixin 展开后再写同名属性即覆盖）。条件块之间不按书写顺序，按固定优先级叠加
  （base ← selected ← expanded ← hover ← active ← focus ← focus-visible ← invalid，disabled 短路，见 2.10）。

### 3.5 属性与值

- **属性名**是 `BoxStyle` / `TextStyle` 的字段名的连字符写法：`corner-radius` → `.corner_radius`、`font-size`、`align-items`……
  `color` 与 `text-color` 互为别名；另有 `typography`（排版 token，一次给字号 / 字重 / 行高，单项属性覆盖它）与 `transition`。
- **写错属性名或枚举值是编译错误**，报在原文位置，属性名带拼写建议（`corner-radus` → `did you mean corner-radius?`）；
  属性表与枚举值从 ui 的样式类型反射生成（`src/yix/style_schema_generated.zig`，`zig build gen-yss-schema`，
  `check-yss-schema` 并入 test-headless）。
- **数字** = 像素 / 原值：`12`、`0.5`、`.5`、`-2`、`12px`。
- **名字** = token 或枚举：
  - token 属性（颜色、间距、圆角、字号、字重、行高、边框宽、尺寸、阴影、透明度、`typography`）的名字按 theme.json 查：
    先按原名精确匹配，找不到再把 `-` 换成 `_`。所以 `bg-primary` 对上 `bg_primary`，主题里的 `text-hairline`、`2xl` 也能直接写。
    写错由 Zig 编译期查表报出并列出可选名。嵌套分组里的 token（`tokens.color.blue.300`）不能直接引用，经语义 token 用。
  - 枚举属性（`direction`、`align-items` …）的名字是框架枚举值，连字符转下划线：`row-reverse` → `.row_reverse`。
  - 宽高的 `grow` / `fit` / `fill`。
  - 映射关系与示例见 [STYLING.md](STYLING.md) 的 token 类别表；用哪份 theme.json 取决于编译该文件的模块（`src/ui` 用
    `src/tokens/default.json`，examples 用 `examples/theme.json`）。
- 颜色：`transparent`；`#rrggbb` / `#rrggbbaa`；`rgb(r, g, b)` / `rgba(r, g, b, a)`（通道 0..255，alpha 0..1 同 CSS）；
  `mix(a, b, 权重)`（颜色混合，权重 0..1，操作数是颜色 token 或颜色值，换主题跟随）；
  `{zig 表达式}` 原样嵌入（逃生口）：它进的是 `ui.css` 的字面量，**必须是编译期常量**；依赖运行期数据的值写参数化样式（那里的 `{zig}` 可以引用参数）。
  例外：普通 `style` 的 `{zig}` 里出现裸标识符 `t`（不是字段 `.t`）时读的是主题（`t: *const ui.theme.Values`，如
  `outline: {ui.Outline{ .color = t.tokens.color.accent, .width = 2 }};`），整个样式改编成无参的主题解析器
  `ui.paramStyle(struct { … }).of(.{})`，换主题重算，与参数化样式同一运行时。这种样式经 `ui.boxFrom` 解析：**不能写 `:hover` 等条件块和
  `transition`**（`.yss` 编译器在那一行报错，不会静默丢弃），交互态与过渡写进同一节点上的另一个普通 style（`style={.{ S.ring, S.ring_states }}`）；
  主题色（包括渐变端点：`gradient: accent bg-primary diagonal;`）直接写 token 即可，条件块里也能写。
- **简写**：`padding` / `margin` 收 1 / 2（竖 横）/ 4（上 右 下 左）个值；`border: 宽 [颜色]`；
  `shadow: md`（token）或 `shadow: x y blur [spread] 颜色`（颜色可为 token / 颜色值 / mix），多层逗号分隔（`shadow: lg, 0 32 80 #00000019`）；
  `transition: …` 整段原文是过渡描述（只能是纯文本），时长可以写 `200ms` / `0.2s` 或设计系统的 duration token（`fast` / `normal` / `slow`，
  编译期按选定设计系统取值），时长与缓动之外的词编译报错。
- `icon-color`：图标着色（icon / image 的 tint），随变体 / 条件走，替代按变体手写的 tint 映射。
- **用在 `<text>` 上的 style**：一个 `style` 可以同时写文字属性与盒属性（`padding` / `background` / `corner-radius`…），文字部分进文本样式、
  盒部分落到文本节点自身（等同 `box=`），不再需要拆成两个样式；它必须是整个 style（不能放进元组），条件块里只能改文字属性；
  文字唯一的条件是 `:hover`（文本节点自己的悬停，例如链接悬停色）。配方（recipe）的文字插槽仍只收文字属性。
- 不做：`:group-hover`（目前只有 Radio 一个用户，用组件里的悬停信号）、`:first` / `:last`。

### 3.6 诊断（节选）

`unknown recipe section`；`properties go inside a slot block`；`not a slot of this recipe`；`unknown condition`；
`not a declared variant or flag`；`applies to flags`；`is a flag: write x or !x`；`not an option of`；`declared twice`；
`unknown mixin`；`takes N argument(s)`；`nested too deeply (recursive mixin?)`；`takes 1, 2 or 4 values`；`empty transition`；
`a transition is plain text`；`is not a style property (did you mean …?)`；`is not a value of …`；`malformed number`；
`mix weight must be within 0..1`；`colors are #rrggbb or #rrggbbaa`；`rgba: alpha is 0..1`；`` `shadow` is a token or `x y blur [spread] color` ``；`empty {} expression`；`must be a Zig identifier`；`is a Zig keyword`（选项名除外：`error` 这类选项生成 `.@"error"`）；
`has the same name as a YSS keyword`（维度名不能叫 base / variant / flag / when / in）。过渡里时长与缓动之外的词在 Zig 编译期报错。

### 3.7 限制

- 依赖运行期数据的连续映射写参数化样式 `style name($p: T) { … }`（见 YSS.md），Zig 才算得出来的写 Zig 函数配 `ui.view.styleBy`。
- 插槽块不能嵌套（`.yss` 编译诊断）；条件块不能嵌套，但目前要到 Zig 编译期才由 `ui.css` 报错，`.yss` 编译器不拦。
- token 名的静态检查在 Zig 编译期：生成的双胞胎在属性那一行按名字取引用（`ui.tokenRef`），拼错的 token 名经映射直接报在 `.yss` 的属性行。LSP 的 token 补全与悬停按**就近的 theme.json**（从文件所在目录往上找；examples 下用
  `examples/theme.json`），找不到时用默认设计系统（`src/tokens/default.json`）；theme.json 改了会自动重新读取。

---

## 4. 概念对照

| React | SwiftUI | Svelte 5 | Yix |
|---|---|---|---|
| `function C(props)` + JSX | `struct C: View` | `.svelte` 组件 | `pub fn C(…) View { return <…/>; }` |
| `useState` | `@State` | `$state` | `var x: T = signal(v);` |
| `useMemo` | 计算属性 | `$derived` | `const y = computed(expr);`（自动跟踪，无依赖数组） |
| 受控 `value` + `onChange` | `@Binding` | `bind:value` | `x: Model(T) = 初值` + `onXChange` |
| `props.children` | `@ViewBuilder content` | `{@render children()}` | `children: View` + `{children}`；具名插槽 `header: View` + 调用方 `header={<…/>}` |
| `cond && <A/>` / 三元 | `if` | `{#if}` | `{if (c) <A/> else <B/>}` |
| `list.map(x => <Row key=…/>)` | `ForEach` | `{#each … (key)}` | `{for (xs) \|x, i\| <Row key={…}/>}` |
| `onClick={() => setN(n + 1)}` | `Button { n += 1 }` | `onclick={() => n++}` | `onClick={n += 1}` |
| CSS-in-JS / Tailwind 变体 | `ViewModifier` | `<style>` | `.yss` 的 `recipe` / `variant` / `flag` |
| `useEffect` / `ref` | `.onAppear` / `@FocusState` | `$effect` / `bind:this` | `effect(…)` / `onMount(…)` / `onUnmount(…)`；`const r = ref();` + `ref={r}` |

**常见写法**

- 表单控件：参数用 `Model(T)`，事件里写 `x = 新值`，调用方 `<Switch checked={on} />` 即双向绑定。
- 带选中态的列表：`{for (items) |item| <Row key={item.id} selected={item.id == current} onClick={current = item.id} />}`。
- 条件样式：数据驱动的状态写成 YSS 的 `variant` / `flag`，模板里 `S.X.of(.{ .kind = kind, .on = on })`；交互态用 `:hover` / `:active` / `:focus-visible`，元素状态用 `:disabled` 等（来源见 3.4）。

## 5. 速查

```zig
// ── Yix ──
pub fn Name(x: T = d, req: T, children: View, header: View, v: Model(T) = d, onX: ?Handler(T) = null, onY: Handler(T)) View
var s: T = signal(init);          const c = computed(expr);          const p = parts(S.Tag, .{ .color = c });
const r = ref();   effect(stmt);   onMount(stmt);   onUnmount(stmt);
<box|row|col|grid|text|icon|image|canvas|spacer …/>     <Comp …/>   <W.Card>…</W.Card>
attr="s"   attr={expr}   flag   {name}   key={…}   ref={r}   state={.{ .disabled = d }}   header={<text>…</text>}
{if (c) <A/> else if (d) <B/> else <C/>}   {if (opt) |v| <A/> else <B/>}   {if (res) |v| <A/> else |e| <B/>}
{switch (e) { .a => <A/>, .b => |payload| <B/> }}
{for (xs) |x, i| <Row/> else <Empty/>}（x 是行数据源，同 key 原地更新）   {for (0..n) |i| <Dot/>}
<col>{header}<text/>{children}<text/></col>（插槽可在任意位置）
onClick={n += 1}  {{ const v = try f(); a = v; }}  {if (c) s else t}  {save()}  {onPress}  {onPick(7)}  {|v| n = v}
onKeyDown={|e| if (e.key == .escape) { close(); e.consume(); }}   onPointerDown={|e| x = e.x}   onScroll={|e| e.stop()}
style={.{ S.a, S.R.of(.{ .k = v }), p.root, ui.view.styleBy(src, f) }}

// ── YSS ──
style name { prop: value; :hover { … } :focus-visible { … } :disabled { … } }
recipe Name [slots(a, b)] { base { … } variant d = x { x { … } } flag f [= true] [{ … } | ;] when f & d in (x, y) { … } }
mixin m(p) { … }      m(arg);
style name($p: T = d, $q: ?T) { prop: $p; prop: $q ?? value; prop: {f($p)}; when $flag & $e in (x, y) & {$p > 0} { … } }   // 视图：S.name.of(.{ .p = 源 })
值：12  .5  12px  bg-primary  column  grow  transparent  #rrggbb  #rrggbbaa  rgba(0, 0, 0, 0.5)  mix(a, b, 0.25)  {zig}
简写：padding: 1 | 1 2 | 1 2 3 4;   border: 1 accent;   shadow: md | 0 4 12 [spread] accent | lg, 0 32 80 #00000019;   icon-color: fg-secondary;   gradient: accent bg-primary [diagonal];
      transition: background 150ms ease-out | background fast ease-out;
```

---

## 6. 未实现与路线

**暂不做，等真实需求再排**（评审过、有设计方向，但当前组件用不到）：

- 片段：组件返回多个根。结构随形态变化的组件现在写成「根固定 + 条件子项」。
- `<span>` 富文本（一段文字里混排不同样式）。
- `:group-hover`（父元素悬停时改子元素）、`:first-child` / `:last-child`（Group 的首 / 中 / 末项圆角）。
- 局部组件、render prop、comptime 组件参数、canvas 的命中形状由绘制函数给出。

**编辑器剩余**：编译失败期间的容错（目前只有光标处的闭合修补）、改名、格式化。

**后续路线**：

| 方向 | 内容 |
|---|---|
| 生态 | storybook 用 Yix 写；pencil→zenit 工具链直接输出 `.yix` |
| Web（DOM） | 同一棵元素树在桌面挂 zenit 节点、在 Web 挂真实 DOM。路线 2026-10-03 已定、尚未排期，决策见 [ROADMAP.md](ROADMAP.md) |
| SSR | 组件只运行一次，正好对应服务端「执行一次、输出 HTML」；hydration 把信号挂到已有 DOM 上。排在 Web 之后，语言层不需要新语法 |

### 静态模板与 typed hole ABI（LP3）

生成双胞胎的 `templateSite` 携带源码模块、组件/分支/行/slot 词法路径、规范化 token、字面量文本和属性记录（布尔、数字、字符串、enum 字面量为有界 tagged value）。字符串 token 保留原字节。Zig 实例化 `ui.view.template.Schema(T)` 输出数据指令流 `instructions` 和 `holes`：site、path、capture 符号与具体类型、receiver / 属性边及具体类型、view 所有权 / 每代一次求值、token 指纹和 occurrence。重复洞保留独立 occurrence、工厂和资源，不能按集合去重。

洞的 `module` 身份使用相对项目/仓库根的 `.yix` 源路径，独立于 checkout 的绝对位置和生成 twin 的输出目录。CLI、LSP 和错误映射使用同一根路径；直接调用编译 API 时，通过 `compileSource` / `compileMappedSource` 或 `compileMappedWithPath` 传入同样的相对源路径。无路径内存编译的身份为 `<memory>`，不能据此建立文件热替换身份。

含复杂属性的容器 lower 成 open/close 指令及 typed receiver 工厂；纯字面量容器和文本进入数据指令。事件、ref、复杂属性、子组件、控制流和 slot 保留编译期类型检查的工厂。属性的原始 token 不是运行时 Zig 求值器；复杂属性/样式引用仍由已编译的 typed receiver 工厂应用。洞及复杂属性 ABI 冻结，缺失、重复、异类接收端、外来 binding、空树、错误根数及无效 payload 在执行任何工厂前拒绝；纯字面量数据不作为洞计数。LP4 的模板解析、兼容性分流、属性编辑解码和发布协议不由这个入口启用。

`build(.comptime_template, ...)` 与 `build(.runtime_template, ...)` 共用同一个 step 和 typed factory 表，只有指令迭代是否展开不同。静态实例化拒绝传入不同于编译期 schema 的数据。`-Ddev-preview=true` 的生成模板走 runtime 指令流；普通 release 编译期直接走原有 view 树，不包含 runtime builder 的可达分支。

`zig build test-template-equivalence` 自动核对全部 `tests/yix/**/*.yix`、组件 `.yix` 与 Storybook Yix story 的覆盖清单；新增/删除源或组件入口后运行 `python3 scripts/gen_template_manifest.py --write`。每个入口使用两组参数，原树、comptime 模板、runtime 模板逐步比较九个状态：初始、首/末 callback、暗色主题、焦点、空格键按下/释放、滚动、清除焦点/浅色主题、再次 callback。Sequence fixture 额外驱动 Show、三分支 Match、keyed For 重排/增加/删除/清空/恢复和 portal。时钟固定且按帧推进，保留真实 IO 后端。

release / preview 两个独立构建之间比较树、求值后的声明、布局、a11y、真实 encoder 命令、业务 signal 写入 trace、订阅边、scope 结构、实际 hook 调用次数与顺序九项投影。逻辑树序对齐节点 id，scope/资源序对齐业务信号和 memo；每个存活 graph 节点必须有已知归属。窗口级 theme/style/a11y 服务按实际身份识别；只有被标记为替代 release theme replay、依赖集合严格属于 theme/generation 且确实观察 generation 的 style effect 才作为 preview 基础设施排除，捕获业务信号不能排除。每个构建内部另比较实际 StyleDecl 的 mask、decode 值和层顺序；跨配置的 raw layers 差异及理由见 [LIVE_PREVIEW_DESIGN.md](LIVE_PREVIEW_DESIGN.md#lp3-projection-representation-boundary)。

Sequence 的七次 A/B/A/B/A/B/A 重建使用实际 runtime 数据指令编辑，另两条 builder 路径以独立 typed wrapper 作为参照；既有洞 ABI 逐项保持相同。每次检查 setup scope、signal 地址/版本/值、Ref 的新根绑定、StateStore id/地址/非默认值和 hook 精确次数。A 的第2/4/6次状态要求 World/graph 节点、订阅/scope 投影及托管 allocator 存活字节完全相等，退出要求分配/释放字节相等。ScrollArea relay cell 只有 owner 及所有 node callback 都退休后，才在后续挂载安全回收；逃逸 callback 仍由 Cx 保活到可回收或窗口退出。

全入口两输入的初始树保存在 `tests/yix/template_equivalence_trees.json`，普通门禁只读且严格比对；显式审阅变更后才可用 `run_template_equivalence_gate.py --write-goldens <release-binary> <preview-binary>` 更新，两个程序必须先成功并跨构建一致。`test-component-view` 另核对 root-host 清单的全部 pin/renderInto 接线和被审计 native host 源摘要；变更后审阅并显式运行 `gen_template_manifest.py --write-hosts` 更新。

两道门禁接入 `zig build test`；缺 fixture、输入、阶段、投影、golden、hook 完成证据，以及重复/未知记录、异常退出、崩溃、超时和 allocator 泄漏均失败，即使此前已经打印成功标记。两组变异覆盖 cleanup、状态重置、失败后显式重挂载、洞路由、paint 差分和 scroll relay 保留。这里验证的是 headless 树、真实 encoder 命令和受测 allocator；原生输入/GPU 截图、IME、多窗口 GUI 和 LP4 模板发布/回滚、完整 OOM 热替换事务仍需各自验收。

纯字面量 box/row/col、基础可见性/焦点/命中/test id 属性和无属性文本 lower 为不依赖工厂的 `literal_open` / `literal_emit` 数据指令。运行时可以插入、删除、嵌套这些节点；已有洞仍须逐 occurrence 唯一消费。复杂属性、style 引用等保留已编译 receiver 工厂。runtime 数据中的借用字符串须由模板版本持有到 view 释放，与现有 attrs/test_id 的借用约定一致；没有在 LP3 启用模板发布。
