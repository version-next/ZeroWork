# 捕获阶段按键属性与声明式焦点（设计说明）

状态：设计 + 第一期实现（见 §6）。范围：Yix 宿主元素的捕获阶段按键属性，以及“焦点目标 / 初始焦点 /
视图模型发起的聚焦 / 子树重挂后恢复焦点”四个声明式焦点能力。
动机：下游应用把视图层全部写成 `.yix` + `.yss` 时，“整窗快捷键先于子控件”“重挂后回焦”这类逻辑
只能留在 Zig 宿主里，靠“把整窗卡片设成可聚焦 + 手挂 `on_event_capture` + 手工按 test_id 快照焦点”实现。
这些都是框架能力缺失，不是应用特例。

行号以本文提交时的 `feat/app-extension-points` 为准。

## 1. 现状

### 1.1 事件分发

- 三阶段模型已经存在：`src/ui/event_dispatcher.zig:1-15` 的注释与 `dispatch`（`:293-401`）。
  路径是 root → target：**捕获**阶段对目标之外的祖先调用 `behavior.events.on_event_capture`（`:319-331`），
  **目标**阶段，**冒泡**阶段由目标的父节点到 root（`:345-359`）。任何阶段返回 `.stop` 都会终止传播；
  `.handled` 只记下“已处理”，传播继续。
- 节点字段：`on_event_capture` / `capture_context`（`src/ui/core/types.zig:3450-3455`），
  与目标 / 冒泡用的 `on_event` / `event_context` 分开。
- `invokeHandler`（`event_dispatcher.zig:1161-1247`）：
  - 捕获阶段只调用 `on_event_capture`；
  - 目标阶段先调用目标**自己**的 `on_event_capture`（DOM 的 at-target 顺序），返回值不是 `.ignored` 时
    目标自己的 `on_event` 不再调用（`:1175-1184`）；
  - 之后依次是 `on_event`，再是专用的 `on_key_down` / `on_key_up`。
- `EventResult`（`src/ui/events.zig:623`）：`.ignored` / `.handled` / `.stop`；`preventsDefault`（`:632`）
  把 `.handled` 和 `.stop` 都视为“阻止默认行为”。
- 按键入口 `cx_input.handleKeyDown` → `routeKeyDown`（`src/ui/core/cx_input.zig:446-580`），处理顺序：
  1. 拖动会话吃掉 Escape；
  2. 正在组字的文本输入独占 Escape：直接对焦点节点分发**完整路径**（`:478-486`）；
  3. tooltip 关闭；
  4. `overlay_stack.handleEscape()` 关闭最上层浮层（`:493`）；
  5. Tab：先发给焦点节点（无焦点时发给内容根），未阻止默认时做焦点遍历（`:495-517`）；
  6. 有焦点时先查 Action 键绑定，再把按键发给焦点节点；Space / Enter 未阻止默认时合成 click（`:521-555`）；
  7. 无焦点时发给 `unfocusedKeyTarget`，即应用挂载的内容根（`content_root`，`:557-576`）。
- 文本输入与输入法（`text_input` / `ime_*`）只发给带 `text_input_client` 的焦点节点（`:599-653`），
  这些是独立的事件种类，按键处理器收不到。macOS 原生层在组字期间把按键交给输入法，
  `handleKeyDown` 只收到输入法没吃的键，以及上面第 2 条的 Escape。
- Yix 的类型化事件（`src/ui/view.zig:6386-6627`）：
  - 宿主元素的 `onKeyDown` / `onKeyUp` 写在 `on_event` 槽，是目标 / 冒泡语义；
  - `KeyPress.consume()` 把结果设为 `.handled`（阻止默认），`stop()` 设为 `.stop`；
  - **组件元素**上的 `onKeyDown` 写在组件根的**捕获槽**（`bindTypedEventsAt(.capture)`），
    `consume` 被升级为 `.stop`，语义是“这个键不交给组件”。
  - 宿主元素没有写捕获槽的 Yix 写法。

### 1.2 焦点系统

- `FocusManager`（`src/ui/focus.zig:43-100`），每个 `Cx`（即每个窗口）一个。
  - `setFocusWithVisibility`（`:273-337`）：每次转移把 `transition_epoch` 加一；依次走 blur / focus 回调与事件，
    回调里发生的更新的转移会让旧转移停止。
  - `visibility` 默认 `.inherit`，即“最近一次输入是键盘才显示焦点环”。点击得焦为 `.pointer` 模态，
    Tab 为 `.keyboard` 模态，程序聚焦（`.programmatic`）不改变模态。
- Tab 序：`focus_order` 按 `tab_index` 和树序排序（`:382-397`）；`focusable` 或 `tab_index` 决定是否进入。
  `focusStep` 跳过不显示的节点（`:495`）。
- 节点销毁时的焦点处理分几条路径，都**不触发** blur：
  - `abandonFocus`（`:349-360`）：组件 scope 释放、回调上下文将要销毁时调用，如 Input（`src/ui/components/input/mod.zig:372`）、
    Popover（`popover/mod.zig:465`）；
  - `unregisterFocusableSilent`（`:400-424`）：在 `freeNodeNow` 里调用（`src/ui/core/cx_node_lifetime.zig:300`）；
  - `invalidateReferencesToEx` 对仍然有焦点的被摘子树调用 `clearFocus()`（`cx_node_lifetime.zig:139-141`）。这是一次真实转移，会发 blur。
- 隐藏（`display: none`）和禁用都**不会**让焦点离开节点；只有 Tab 遍历会跳过不显示的节点。
- 焦点作用域：`pushScope` / `popScope` / `removeScope`（`focus.zig:613-700`），配合 `FocusScopeConfig{trap, auto_focus}`（`:23`）。
  - 浮层栈（`src/ui/overlay_stack.zig:166-183` 的 `FocusConfig{trap, auto_focus, restore}`）在打开时记下 `previous_focus`，
    关闭时写入 `pending_focus_restore`（`:541-545`）；
  - `cx_render.render` 在零脏快路径**之前**调用 `drainOverlayFocusRestore`（`src/ui/core/cx_render.zig:119`，实现见 `cx_node_lifetime.zig:182`）。
  - 结论：Modal / Sheet / Popover 已经有“进入保存、离开恢复”，普通（非浮层）元素没有。
- 焦点环：`hooks.useFocusRing`（`src/ui/hooks.zig`，外观由 `FocusRingConfig` 配置）。
  Yix 写法是 `focusable` / `focusRing` / `onFocus` / `onBlur`（`view.zig:6631` 的 `bindFocus`）。
- 点击得焦：`resolvePointerDownFocus`（`cx_input.zig:159`）沿父链找第一个可聚焦节点或 `.preserve`。
  **点击不可聚焦区域会清除焦点**（`:121-122`）。之后按键落到内容根。
- 命令式 API：`Cx.setFocus` / `clearFocus` / `isFocused`（`core.zig:2464-2478`），
  `focus_manager.setFocusWithReason` / `setFocusWithVisibility` / `getFocused` / `pushScope` / `popScope`。
  Yix 里没有对应写法，模板只能经 `ref` 拿到节点后交给宿主。

## 2. 下游需求（ZeroWork 归纳）

| 模式 | 现状写法 | 需要的能力 |
|---|---|---|
| A. 整窗 / 区域快捷键先于子控件（设置窗口 Esc、⌘W、⌘,；主窗口导航；快速连接；认证质询） | 在容器上手挂 `on_event_capture`。设置窗口还把卡片设为可聚焦，并每帧在无焦点时把焦点塞给卡片，因为无焦点时按键只到窗口根 | Yix 的捕获阶段按键属性；容器**不需要可聚焦**；无焦点时窗口级处理器也能收到 |
| B. Escape 分层消费 | 宿主里按优先级手写：预览 → 页面 tooltip / popover → 原地编辑取消 → picker → 关窗 | 框架已有的层次：拖动 → 组字 → tooltip → 浮层栈 → 捕获链 → 目标 → 冒泡。应用自己管理的层由 view-model 判定 |
| C. 重挂后恢复焦点 | 重挂前按 **test_id** 记下焦点字段与光标 / 选区，重挂后找回、`setFocus`、恢复选区，分两阶段延迟到挂载之后 | 按**稳定的运行时标识**自动快照与恢复，含文本选区；目标挂载后才执行 |
| D. 打开时的初始焦点 | 打开时 `setFocus(输入框)`；对话框按模式选择初始焦点 | 声明式的初始焦点，以及 view-model 按条件指定目标 |
| E. 关闭弹层后回到触发者 | 记下锚点 test_id，关闭后 `find` + `setFocus`；AI 面板按业务标识回焦到终端 | 浮层已有 `FocusConfig.restore`；非浮层面板需要“进入保存、离开恢复”的元素级作用域 |
| F. 跨区域焦点交接（终端 ↔ 浮层 / AI 面板） | 先检查“当前焦点在面板内”，再 `setFocus` 交出去 | view-model 按标识发起聚焦，框架处理“目标就绪后执行”和“被更新的焦点转移取代” |

## 3. API

### 3.1 捕获阶段按键：`onKeyDownCapture` / `onKeyUpCapture`

```yix
<box testId="settings.window" onKeyDownCapture={|e| vm.windowKey(e)} onKeyDown={|e| vm.windowKeyLate(e)}>
```

- 适用元素：box / row / col / grid / canvas，与 `onKeyDown` 相同。事件值是 `ui.view.KeyPress`。
- 语义：写在节点的捕获槽（`on_event_capture`）。只要按键路径经过这个元素就会收到：
  - 焦点在它自身或子树内；
  - 或者窗口没有焦点、而它在内容根到目标的路径上。无焦点时目标就是内容根，所以把处理器写在窗口模板的根元素上即可。
  - **容器不需要可聚焦。**
- 顺序：root → … → 该元素的捕获处理器 → 目标的捕获处理器 → 目标的 `onKeyDown` → 冒泡。
- 消费语义沿用 `KeyPress`，与 DOM 一致：
  - `e.stop()`：停止传播，目标与冒泡阶段都收不到，同时阻止默认行为。整窗快捷键用这个；
  - `e.consume()`：只阻止默认行为（Tab 遍历、Space / Enter 合成 click），目标仍收到这个键。
  - 都不调用就原样放行。
  - 例外：捕获处理器所在元素**本身就是目标**时，沿用现有 at-target 规则（`invokeHandler`），`consume` 也会跳过它自己的 `onKeyDown`。
- 输入法：`KeyPress` 新增 `composing: bool`，表示焦点所在的文本输入正在组字。组字期间**捕获处理器不会被调用**，
  组字中的键（目前只有 Escape 能到这里）归输入框。冒泡处理器照常收到，可以读 `e.composing` 自行判断。
  文本输入与 IME 事件不经过这些处理器。
- 只做键盘：指针的捕获阶段（`onPointerDownCapture`）放到后续（§6），理由是指针已有指针捕获和命中规则，需求不同。
- 与组件根捕获槽的关系：组件元素上的 `onKeyDown` 同样写在组件根的捕获槽。
  如果组件模板的根元素自己写了 `onKeyDownCapture`，调用方再给这个组件写 `onKeyDown`，
  挂载时会报 `error.ViewCaptureSlotTaken`，与现有的槽占用规则相同。
  组件元素上不能写 `onKeyDownCapture`（编译期诊断）：那里的 `onKeyDown` 本来就先于组件自身处理。

### 3.2 焦点标识：`focusId`

```yix
<W.Input focusId="settings.search" … />
<box focusId={row.id} focusable>…</box>
```

- 为什么不复用 `testId`：test_id 是测试 / 自动化接口，改名不应改变运行时行为，
  而且测试会给同一节点或部件随意命名、可能重复。
- 为什么不复用 `key`：`key` 是 `{for}` 行内的对账标识，只在一个列表里唯一，不是字符串，也不在单个元素上。
- 所以单独引入 `focusId`，它是运行时语义。值是字符串，可以是字面量、表达式，或在挂载时读取的源。
  框架复制一份，模板里的字符串不需要活过挂载。
- 宿主元素和组件元素都能写，写在组件元素上时作用于组件根。
- 目标解析：带 `focusId` 的节点本身可聚焦就聚焦它；否则聚焦它子树里第一个可聚焦、可见的节点，树序优先。
  所以写在 `<W.Input>`、`<W.Select>` 这类根不一定是焦点节点的组件上也成立。
- 唯一性：在**一个窗口**（`Cx`）内按名字查找，可以再限定在某个子树内（§3.4、§3.5）。重名时取第一个合格的。

### 3.3 初始焦点：`autoFocus`

```yix
<W.Input focusId="settings.search" autoFocus … />
```

- 挂载时登记，在节点**就绪后**聚焦它，语义同 React 的 `autoFocus`：
  - 就绪 = 已挂到窗口树上、显示、可聚焦（或子树里有可聚焦节点）、未禁用（`a11y.disabled`）、不在当前活动陷阱作用域之外。
  - 执行时机见 §4.4。
- 登记之后只要发生过**任何**焦点转移（用户点击、Tab、命令式 `setFocus`、其他声明式聚焦），这次 autoFocus 就作废，
  不会在之后抢回焦点。
- 值在挂载时取一次（布尔字面量或源的当前值）；要“条件成立时再聚焦”，用 `focusRequest`。
- **对话框 / 弹层里的 autoFocus**：目标在一个未压栈的陷阱作用域里（`W.Modal` / `W.Sheet` / 捕获焦点的 `W.Popover`
  常驻挂载、关闭中）时不就绪，也不会因之后的焦点转移作废：它改为“随作用域聚焦”，作用域每次打开都聚焦它
  （`FocusObserver.entry_target`）；在打开中的陷阱里挂载并获焦的 autoFocus 同样成为之后每次打开的默认。
  打开时的完整进入规则（已在里面不动、`focusRequest`、组件的 `initial_focus`、autoFocus、第一个控件、
  等待时的占位与升级、用户输入结束等待）见 `docs/design/popover-initial-focus.md` §5.3
  （`FocusManager.pushScopeWith` / `scope_entry`，取代原单槽位 `pending_scope_focus`）。

### 3.4 视图模型发起聚焦：`focusRequest`

```zig
// view-model
focus: *ui.Signal(ui.view.FocusRequest),
pub fn openSearch(vm: *Vm) void { vm.focus.set(vm.focus.peek().to("settings.search")); }
pub fn leaveEditor(vm: *Vm) void { vm.focus.set(vm.focus.peek().blur()); }
```
```yix
<box testId="settings.window" focusRequest={vm.focus}> … </box>
```

- `ui.view.FocusRequest = struct { id: ?[]const u8 = null, seq: u32 = 0 }`：
  - `to(id)` 返回 `seq + 1` 的新请求；
  - `blur()` 返回 `id = null` 的新请求，表示“焦点在这个子树里就清掉”。
  - 是“请求”而不是“状态”。同一个目标连续请求两次，靠 `seq` 区分。
  - 挂载时源的当前值只作为基线，不执行；重挂模板不会重放旧请求。
- 作用范围：写在哪个元素上，就只在那个元素的子树里按 `focusId` 查找。一个窗口的模板根就是整窗范围。
- 执行：
  - 目标就绪就立刻同步聚焦，程序聚焦，焦点环按输入模态继承；
  - 未就绪（还没挂载、同一批稍后才挂、隐藏、禁用）就挂起，见 §4.4。
  - 挂起的请求在以下情况作废：被更新的请求取代、发生任何其他焦点转移、元素卸载。
- `id` 字符串由框架复制，view-model 可以传临时字符串。
- 读侧（“现在焦点在哪个 `focusId` 上”的信号）放到后续，见 §6。

### 3.5 子树重挂后恢复：`focusRestore`

```yix
<box testId="settings.content" focusRestore>
    {switch vm.page} … {/switch}
</box>
```

- 写在**不随内容重挂**的容器上。对它的子树起作用：
  1. 焦点进入子树内某个带 `focusId` 的目标（或其后代）时，框架记下这个 `focusId`。
  2. 这个节点因为子树重挂而被销毁、焦点被动丢失时，框架保存一份“待恢复”：`focusId`、焦点环是否显示，
     以及能读到的话焦点节点的文本选区（`text_input_client.selection`）。
     “被动丢失”指 `abandonFocus`、`unregisterFocusableSilent`、`invalidateReferencesTo` 三条路径；
     主动 `setFocus(null)` 或 blur 不算。
  3. 之后子树里出现同名的就绪目标时，把焦点放回去：可见性按丢失前的状态；
     目标有 `text_input_client.set_selection` 时恢复选区，越界会被夹到文本长度内。
- 待恢复的条件：
  - 窗口当前仍然**没有焦点**；
  - 丢失之后没有发生过其他焦点转移；
  - 恢复区本身还在。
  - 三条任一不满足就作废。新页面没有同名目标时就保持挂起，直到上述条件失效。
- 优先级：同一轮里依次处理 `focusRequest` → `focusRestore` → `autoFocus`。前一项成功聚焦会让后面的作废，
  因为它们都要求之后没有发生焦点转移。

### 3.6 与命令式 API 的关系

- 命令式 `cx.setFocus` / `focus_manager.*` 全部保留，行为不变。
- 规则只有一条：**后写者赢**。
  - 任何焦点转移（不论来源）都会作废更早登记、尚未执行的声明式聚焦（autoFocus、挂起的请求、待恢复）；
  - 声明式聚焦本身也是一次普通的程序转移，之后的命令式调用照样覆盖它。
  - 实现上靠比较 `FocusManager.transition_epoch`。
- 浮层的 `FocusConfig.restore` 不变，与这里的机制互不调用。
  浮层关闭的回焦在 render 开头先执行，之后才处理声明式挂起项。
- 焦点作用域的进入占位（`docs/design/popover-initial-focus.md` §5.3）是唯一的例外：它是一次普通的程序转移，
  但若它是唯一发生的转移，之前挂起的 `autoFocus` / `focusRequest` / `focusRestore` 改打新戳，不被它作废。

## 4. 与现有系统的关系与边界

### 4.1 多窗口
登记表和挂起项都放在 `Cx` 上（`cx.focus_targets`）。每个窗口独立，查找不会跨窗口。
跨窗口回焦（设置窗口关闭后回到主窗口的打开者）是窗口激活问题，不在本设计范围，由宿主处理。

### 4.2 浮层 / portal
- 子树查找按真实节点父链。portal 里的内容不是触发元素的后代，所以要在 portal 内容里写 `focusRequest`，
  或者在窗口根上写（窗口根的子树包含 portal）。
- 活动的陷阱作用域（Modal）之外的目标视为“未就绪”，保持挂起。Modal 关闭会回焦，这次转移让挂起项作废。

### 4.3 禁用与隐藏
- 目标显示为 `display: none`（`visible={false}`）、`a11y.disabled`、不可聚焦且子树里也没有可聚焦节点时，视为未就绪。
- 已经拿到焦点的节点之后被隐藏或禁用，焦点**不会**因此自动移走，与现状一致。

### 4.4 延迟执行的时机
- 挂起项在 `Cx.render` 开头处理：位置紧跟浮层回焦，同样在零脏快路径之前（`Cx.settlePendingFocus`）。
- 登记和挂起时都会请求重绘，所以“同一批稍后才挂上”的目标在下一帧开头就会被找到。
- `focusRequest` 在请求当下先同步尝试一次：目标已经在树上就立即生效，view-model 写完信号后焦点马上就到位。
- 在 after-layout 钩子里重挂的内容（ZeroWork 设置窗口的两阶段 settle）在下一帧开头恢复，与旧宿主的时机相同。

### 4.5 焦点环
- 声明式聚焦都是 `.programmatic` 转移：焦点环按当前输入模态显示，键盘模态显示、指针模态不显示。
- 恢复焦点时沿用丢失前的可见性。
- `useFocusRing` / `FocusRingConfig` 不变。

### 4.6 无障碍
所有聚焦都走 `setFocusWithVisibility`，a11y 焦点通知（`a11y_bridge.notifyFocusChange`）与原生文本输入会话
（`on_focus_settled`）照常同步。捕获处理器不影响无障碍树。

### 4.7 成本
- 没写这些属性的元素不付任何代价。
- 焦点转移时，登记表非空才沿父链查一次登记（线性表，条目数等于写了 `focusId` / `focusRestore` / `focusRequest` 的元素数）。

## 5. 迁移影响

- 现有组件与应用：
  - 新增的 `KeyEvent.composing` 带默认值；
  - `FocusManager` 新增的观察者默认为空；
  - `Cx` 新增的 `focus_targets` 默认为空表。
  - 不写新属性时没有任何行为变化，现有测试不改。
- 下游 ZeroWork 设置窗口（S-6）前后对照：

旧（宿主 Zig）：
```zig
card.behavior.events.capture_context = self;
card.behavior.events.on_event_capture = onWindowKey;   // Esc / ⌘W / ⌘,
card.setFocusable(true);                                // 为了无焦点时也能收到键
ui.hooks.updateFocusRingConfig(cx, card, .{ .width = 0 });
// WindowHook：每帧 if (focused == null) cx.setFocus(card)
// 重挂前 page.captureFocus()（按 test_id + 光标），settle 后 page.restoreFocus(snapshot)
```
新（模板 + view-model）：
```yix
<box testId="settings.window" style={S.window_root}
     onKeyDownCapture={|e| vm.windowShortcut(e)}
     onKeyDown={|e| vm.windowEscape(e)}
     focusRequest={vm.focus}>
    <box testId="settings.panel" style={S.shell}>
        … <W.Input focusId="settings.search" autoFocus … />
        <box testId="settings.content" focusRestore> {switch …} </box>
```
- `windowShortcut`：⌘W / ⌘, 关窗并 `e.stop()`；正在录制快捷键时放行。
- `windowEscape` 在冒泡阶段：内层控件（原地编辑、快捷键录制）先拿到 Escape 并 `stop`，
  没人要时才按 view-model 的层次收起预览、picker，最后关窗。
- 页面字段写 `focusId`（推荐与字段的业务 id 同名）。

## 6. 分期

本期实现（最小可用子集，足以收回 S-6）：
1. `onKeyDownCapture` / `onKeyUpCapture`，`KeyPress.composing`，组字期间不调用捕获处理器；
2. `focusId`、`autoFocus`、`focusRequest` + `ui.view.FocusRequest`，含挂起与“后写者赢”；
3. `focusRestore`，含文本选区恢复。

后续（理由）：
- `focusReturn`，元素级“进入保存、离开恢复”：浮层已有，S-6 用不到。非浮层面板（AI 面板、内联对话框）需要，
  可以直接复用本期的观察者和挂起机制。
- 读侧信号（`focusWithin` / 当前 `focusId`）：S-6 的 Escape 分层改用冒泡顺序后不需要它；
  加它要定义“焦点变化 → 信号写入”的批次时机，单独评审。
- 声明式陷阱作用域（`focusScope={.{ .trap = true }}`）：Modal 已有，非浮层陷阱的需求还不明确。
- 指针捕获阶段属性：语义与指针捕获、命中规则交织，没有下游阻塞。
- 跨窗口回焦：属于窗口激活，宿主处理。
