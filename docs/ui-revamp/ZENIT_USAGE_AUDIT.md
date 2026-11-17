审查结论：**ZeroWork 确有绕过组件契约、重复管理交互状态的问题，但现有证据不支持“这批上游改动多数是在补 ZeroWork 的误用”。** 更准确的判断是：应用层复杂度放大了框架缺陷，也把若干产品偏好推进了框架默认行为；这两件事需要分别治理。

全程只读，未修改文件、未运行项目或测试、未联网。下文的“可触发”来自源码路径和回归用例审阅，不代表本次执行过复现。

**范围与计数**

- ZeroWork：`feat/ui-arch-revamp @ 897dc001`。
- zenit：`feat/app-extension-points @ f3a56172`，main 为 `c669f0bb`；vendor 锁定同一 `f3a56172`。
- `main..feat/app-extension-points` 共 **275 个提交**：174 个实现/修复提交，另有 85 个文档、8 个合并、6 个构建/测试/索引维护、2 个 Storybook 新示例提交。
- 以下按 **174 个实现/修复提交**归类；合并与随附文档不重复算成能力或缺陷。review 中 U0/U1、焦点系列和 genie 后续均已纳入。
- 一个提交混合多项内容时，按主要目的计数，混合部分另行指出。因此数量不能解释成独立缺陷数量。

| 类别 | 条数 | 判断 |
|---|---:|---|
| A 通用能力 | **101** | 保留，部分应完善接口设计 |
| B 框架缺陷 | **67** | 保留修复；其中包含本分支新能力引入后的修复 |
| C 应用用法补丁 | **1** | 迁移应用后可撤；置信度中等 |
| D 产品定制 | **5** | 优先改为应用配置或明确的可选策略 |
| 合计 | **174** | |

这里没有把“ZeroWork 不再调用某接口”直接判为 C，也没有把提交标题中的 `fix` 自动视为 B。

---

**先说最重要的应用层发现**

**1．AI 虚拟列表违反了已有的 Scope 契约，优先级最高。**

证据在 [ai_history_view.zig:21](../../src/features/ai/pane/view/ai_history_view.zig#L21)：用 `mountWithContext` 创建 VirtualList，但 [同文件:53](../../src/features/ai/pane/view/ai_history_view.zig#L53) 把行内 `renderInto` 挂在调用方 `self.scope` 下。

官方 [view.zig:3885](../../vendor/zenit/src/ui/view.zig#L3885) 明确要求：`renderInto` 的 parent_scope 必须属于容器的所有者；池化组件应把自己的 Scope 交给回调。`mountScoped` **在 main 已存在**，不是这 275 个提交补出的能力。

当前父 Scope 与列表一起释放的路径可能掩盖问题；列表单独释放时，存在行 effect 比节点活得更久的风险。本次未动态证明现有操作序列必然触发悬垂访问。

整改：改用 `mountScoped`，回调接收列表 Scope，再传给 `renderInto`。同时处理下列组件内部改写：

- [ai_history_view.zig:26](../../src/features/ai/pane/view/ai_history_view.zig#L26)：清空组件事件和主 before-render hook。
- `:30` 隐藏其余内部子节点。
- `:34` 改写 `state.container_node`。
- `:36` 覆盖内容节点 event_context。

这些已超出“设置公开 props”。先修 Scope 是小改；把外层滚动与虚拟化组合收敛为有契约的适配器是中改，风险在滚动补偿、可访问性和动态高度。

对照：zeditor 的编辑器生命周期明确保存业务状态、释放旧视图，见 `zeditor-new/src/zdoc_app/editor_island/tab_manager.zig:582`；官方池化回调契约比参照项目更直接。**此问题不能靠撤掉 `translate_content` 来修复。**

**2．retained detach / reparent 不是禁用操作，但 ZeroWork 把它变成了跨系统协议。**

主要入口：

- [workspace.zig:2715](../../src/features/workspace/view/workspace.zig#L2715)：明确要求内容节点只搬、不复制。
- [workspace.zig:2808](../../src/features/workspace/view/workspace.zig#L2808)：停靠时 retained detach。
- [ai_host.zig:4121](../../src/features/ai/host/ai_host.zig#L4121)、`:4187`：在分屏与浮动 chrome 之间搬同一内容节点。
- [retained_panel.zig:54](../../src/features/shell/view/retained_panel.zig#L54)：隐藏面板脱树、重新登记 identity。
- [float_layer.zig:815](../../src/shared/ui/float_card/float_layer.zig#L815)：identity 变化后销毁、重建 AnchorTransition。

main 的 `detachChildRetained` 本来就会失效输入身份；它保留节点不等于保留旧 handle 的有效性，见 [cx_node_lifetime.zig:174](../../vendor/zenit/src/ui/core/cx_node_lifetime.zig#L174)。

参照项目并非完全不用 retained detach：zeditor `zeditor-new/src/zdoc_app/chart_view/panel.zig:2490` 也使用它，但随后释放候选/旧视图；这不能作为“同一复杂内容树在多个宿主间长期迁移”的先例。其普通编辑器切换则保存文档/光标状态并重挂视图。

建议：保留终端、会话、文档等业务资源；让轻量 UI 随目的地 Scope 挂载。确须保留节点的终端表面，集中到一个迁移适配器，统一完成脱离前关闭浮层、清理输入、迁移、恢复滚动和焦点。不要把这些步骤散落在 Workspace、AiHost、Panel、Transition 中。

规模大，风险高。需要保留滚动、选区、IME、后台任务等行为，不能直接改成“所有内容销毁重建”。

**3．混用 Zig 与 Yix 合法；跨边界寻找、修补组件内部结构才是问题。**

明显实例：

- [ai_host.zig:3354](../../src/features/ai/host/ai_host.zig#L3354)：递归按 test_id 找节点，随后根据 `text.parent` 改气泡内部列宽。
- [window_frame.zig:17](../../src/features/settings/view/window_frame.zig#L17)：按 test_id 搜索设置内容根。
- [bmc_ikvm/editor.zig:1117](../../src/plugins/bmc_ikvm/editor.zig#L1117)：直接修改 Select wrapper、trigger、panel，并安装排版重写 hook。
- 前述 VirtualList 的状态、事件、hook 改写更严重。

`setStyleInline` 本身是公开 API；官方也允许 `setup`、Result、`parts`。应区分：

- 对自己拥有的定位盒写几何：合理。
- 对公开部件做有限覆盖：允许，但应使用 `parts`/具名样式。
- 依赖内部 child 顺序、parent 关系、event_context 类型：脆弱耦合。
- 用 test_id 充当生产组件接口：应整改。

对照并不支持简单的“别人没这么做”：znote `znote/src/shell/chrome/prop_form.zig:533` 同样索引 Tabs 内部子节点；`znote/src/shell/chrome/kit.zig:110` 递归寻找图标。zeditor `zeditor-new/src/zdoc_app/save_prompt.zig:44` 也修改 Modal 的公开部件。它们是对照材料，不是无条件的规范样本。

整改：业务可变值进入 Source/Model；几何通过调用方样式或明确部件接口传入；跨卸载边界使用 live Ref。当前 [ai_composer.yix:29](../../src/features/ai/composer/view/ai_composer.yix#L29) 已采用 Textarea Result Ref、受控值和 slots，是可沿用的方向。规模中，风险中。

**4．`layer_materials` 是应用自建的第二套材质/拓扑系统。**

它不仅提供颜色：

- [layer_materials.zig:9](../../src/shared/ui/styles/layer_materials.zig#L9)：占用 `component_name` 标注材质角色。
- `:147` 遍历普通节点及 portal，推导 owner、层级、顺序。
- `:246` 在 after-layout 同步。
- `:268` 统一覆盖 shadow。
- `:274` 为 portal 根写 glass、清 border/outline。
- `:382` 插入补偿节点，`:398` 按几何生成补偿图形。

源码已经记下误判的结果：`:117`–`:129` 特判 toast、Tooltip、AnchorTransitionLayer，避免全窗刷底或浅底浅字。这是**应用材质策略识别错对象**，不应归因成 zenit 的普通浮层缺陷。

对照：znote `znote/src/shell/chrome/compose.zig:75` 明确挂顶部磨砂带；zeditor `zeditor-new/src/markdown/media_glass.zig:25` 给自己拥有的媒体表面应用材质。两者都没有这里这种按全窗口拓扑推断、重新刷所有浮层的策略。

整改：材质归创建者，主题归 token/recipe；KVM 视频上方的可读性材质单独声明。先让原生 Menu、Popover、Modal 保持原生表面，再逐步删除全局识别、补偿和特殊排除表。确需多层透明补偿的设计，应作为独立应用组件保留，不能静默作用于所有 portal。

规模大，视觉风险高。移除此模块会降低 `structure_revision` 等 API 的本项目需求，**但不证明这些通用 API 应撤回。**

**5．`/tree` 超过 256KB 是历史事实，但不能直接推导渲染性能。**

[REQUESTS.md:99](../human-feedback/REQUESTS.md#L99) 记录：加入确认框后，主窗口完整序列化超限；此前也已接近缓冲上限。harness [command_queue.zig:8](../../vendor/zenit/src/test_harness/command_queue.zig#L8) 的 256KB 限制是 **JSON 响应限制，不是 UI 节点预算**。新增 paint facts 同样增加字节数。

当前已有改善：

- [main_window.zig:704](../../src/app/main_window.zig#L704) 把关闭的 settings/AI 面板脱树。
- 连接编辑器按需创建独立窗口。
- e2e 改用 query、子树、visible-only。

但这些脱树面板仍保留 Scope、资源和相关宿主 hook；“不在树里”不等于完全没有后台成本。

建议按功能建立节点、Scope、hook、挂载次数预算；普通对话框可以常驻，重型面板按需挂载，草稿和选区保存在模型。保留 `POST /tree`：大应用需要有界查询，不能把这个诊断能力判为 C。规模中到大，风险在草稿恢复、首次打开延迟。

**6．逐帧轮询过重；不是每个 signal.set 都会引起重绘。**

- [ai_host.zig:7581](../../src/features/ai/host/ai_host.zig#L7581) 的 PollHook 在 after-layout 做业务泵送、同步停靠、主题刷新、重建对话、尺寸校正等。
- [bmc_ikvm/views.zig:564](../../src/plugins/bmc_ikvm/views.zig#L564) 持续刷新几何、提示和浮层，并按 33/250ms 调度。
- [bmc_ikvm/editor.zig:1068](../../src/plugins/bmc_ikvm/editor.zig#L1068) 每帧递归检查、改写原生控件排版。
- [background_layers.zig:78](../../src/features/shell/view/background_layers.zig#L78) 每帧清除其他路径可能重新写回的背景，表现出两个写入者争夺同一属性。

不过，zenit [signal.zig:315](../../vendor/zenit/src/ui/reactive/signal.zig#L315) 会跳过相等值；Composer 多个 setter 也有比较保护。不能把上述代码直接描述成“每帧所有 effect 重跑”。

参照 zeditor `zeditor-new/src/zdoc_app/editor_island/mod.zig:932` 也有大型 before-render 调度器，但很多路径消费 pending 事件，并使用有声明的 hook 范围。这说明“有帧回调”不是问题，**静止时仍遍历、重算，以及样式所有权冲突**才是重点。

整改：异步结果、主题、配置、布局变化分别发布 revision；纯颜色/排版改为主题重放；保留确需逐帧的动画、视频和惯性逻辑。按实际写入范围审计 `.self` / `.dirty_marking`，不能仅为缓存把 hook 虚标为安全。规模中，风险中。

**7．悬停、焦点、Esc 有重复来源；拖动则已部分复用内置机制。**

两处具体冲突：

- [ai_user_message_view.zig:49](../../src/features/ai/pane/view/ai_user_message_view.zig#L49) 用 `useHover`，`:76` 又用鼠标矩形检测决定 hovered。上游“落地后静止鼠标不 hover”的策略，挡不住应用自己的矩形判断。
- [ai_composer_controls.yix:114](../../src/features/ai/composer/view/ai_composer_controls.yix#L114) 在原生 Popover 内容中捕获 Esc；[controls_view.zig:677](../../src/features/ai/composer/view/ai_composer_controls_view.zig#L677) 按 model、usage 固定顺序关闭，同时 Popover 自己也声明 `closeOnEscape=true`。这形成两个关闭裁决入口；不能仅凭静态代码断言目前一定会一次关两层。

[overlay_host.zig:249](../../src/shared/ui/overlay/overlay_host.zig#L249) 还通过帧计数管理非模态卡片焦点。它与原生 Popover 的语义不同，不能直接换成模态浮层，但应缩小为一套明确的非模态卡片协议。

对照：znote `znote/src/shell/chrome/state.zig:135` 明确让 Popover 自己 toggle；zeditor 仍有自管 tab tooltip 和 outside-click，所以也不是完全统一的参照。

整改：原生浮层的 Esc/外部点击/焦点归原生栈；应用只决定业务互斥和关闭后的业务动作。消息操作区保留一个 hover 来源。浮动卡片统一管理自己的非模态语义。

拖动不能笼统判为手搓错误：[float_layer.zig:384](../../src/shared/ui/float_card/float_layer.zig#L384)、`:400` 已使用 `drag.Binding.attach`；应用额外实现的缩放、惯性、滑动收起属于产品能力。规模中，焦点和输入回归风险高。

**8．AnchorTransition 的核心问题是生命周期耦合和产品偏好进入默认值。**

应用同时管理：

- retained detach 的 identity；
- 动效 hold 导致的 `display:none`；
- `keep_attached`；
- 过渡重建；
- 焦点进入；
- 停靠后的延迟尺寸稳定。

见 [retained_panel.zig:19](../../src/features/shell/view/retained_panel.zig#L19)、[float_layer.zig:815](../../src/shared/ui/float_card/float_layer.zig#L815)、[workspace.zig:2985](../../src/features/workspace/view/workspace.zig#L2985)。

建议先形成稳定展示宿主，再简化动效：移动的是外壳或快照，内容的业务所有者不随视觉位置变化；确需迁移时，在过渡终态提交。统一由一个组件拥有 transition，业务层只传“展示状态、锚点、模式”。

官方 [ANCHOR_TRANSITION.md:143](../../vendor/zenit/docs/ANCHOR_TRANSITION.md#L143) 的 `attach(scope, ...)` 已提供生命周期入口；手动 `create/destroy` 不是错误，但当前为脱树重建 transition 增加了协议负担。规模大，风险高。**几何、纹理缓存、滚动条捕获等通用正确性修复仍应保留。**

---

**C/D 项逐条判断及撤除前提**

| 提交 | 类别 | 依据、标准替代与撤除前提 |
|---|---|---|
| `c48c9de4` legacy 标题栏支持 `windowRegion` | **C，中等置信度** | ZeroWork [process_windows.zig:125](../../src/app/process_windows.zig#L125) 用 `.custom_inset`，而 [header.yix:37](../../src/features/settings/view/header.yix#L37) 用新区域语义。main 已有 `.chrome = .{ .custom = .{} }` 配套路径，官方 [window_chrome/main.zig:55](../../vendor/zenit/examples/window_chrome/main.zig#L55) 用 WindowHeader/DragRegion/client 区域；[runtime.zig:974](../../vendor/zenit/src/zenit_app/runtime.zig#L974) 区分新旧回调。先给 AuxWindow Spec 和所有窗口创建入口增加新 chrome 配置，迁移拖动区域及 controls ownership，再撤 legacy 桥接。保留旧 API 兼容本身有价值，因此不是高置信度的“错误调用”。 |
| `9e3720cc` 替换焦点指示器 | **D** | 历史调用在 `a265f663^:src/shared/ui/zenit_ext/focus_fill.zig:23`；该实现按颜色反推角色、逐帧覆盖背景，失焦恢复到了错误悬停色。ZeroWork **已在 `a265f663` 删除并恢复原生焦点环**；两个参照项目未找到此接口调用。建议撤应用特制的替换协议，保留既有 FocusRingConfig。当前 ZeroWork 无需再改；撤前仍应检查框架内部依赖。 |
| `ca5fddf7` 默认展开 ease-out、首帧前进 | **D，混合项** | 为 AI launcher 展开初期“约117ms看不见”调整整体时钟。应用 [float_card_motion.zig:48](../../src/shared/ui/styles/float_card_motion.zig#L48) 直接依赖框架默认。可配置 easing 是 A；把特定观感设为全局默认是 D。先在应用声明完整 motion preset，再恢复保守默认；首帧零进度是否应推进应另立通用时序契约。不要整提交盲撤。 |
| `9b7fb6cb` 落地后压住静止鼠标 hover | **D** | 框架只对 AnchorTransition landing 特判，其他场景变化仍重新命中。应用自己的 [Reveal:76](../../src/features/ai/pane/view/ai_user_message_view.zig#L76) 又把几何覆盖视为 hover，语义不统一。先删除双重 hover 来源，确定产品是否需要落地抑制；需要时以局部、显式策略实现，再撤全局特判。不是命中索引正确性修复。 |
| `b8fbce3c` 静态纹理模型并默认 genie | **D，混合项** | 当前默认使所有调用者改变 hold/layout 行为，且 genie 网格仅 Metal 实现，其他后端退化。应用 [float_card_motion.zig:4](../../src/shared/ui/styles/float_card_motion.zig#L4) 明确依赖这一默认。静态纹理优化属于 A；默认 genie、时长和通用 hold 语义绑定属于 D。先显式选择 `shape`、hold、时长，消除由 `display:none` 推断业务关闭的路径；保留缓存和正确性修复，仅剥离默认策略。 |
| `60795a62` expand 捕获前结束全部颜色过渡 | **D** | 触发是 [Composer Textarea:29](../../src/features/ai/composer/view/ai_composer.yix#L29) 打开同回合取焦点。框架 [render_engine/mod.zig:331](../../vendor/zenit/src/ui/core/render_engine/mod.zig#L331) 强制推进背景、边框、文字颜色，并提前触发完成回调。冻结快照与继续变化的活内容不同，不足以证明必须提前结束整个子树动画。先在应用明确“入场先完成焦点外观/落地后取焦点/飞行中局部禁用颜色过渡”之一，保持键盘与 IME 进入契约，再移除强制完成。 |

D 的判断针对**默认策略和当前需求来源**，不代表其中数学、缓存、可配置接口没有通用价值。

---

**其余 A/B 项的逐条清单**

为控制长度，下表使用证据代号；每个代号同时给出 ZeroWork 位置和官方/参照处理方式。历史编译错误用 spike 中保留的触发写法；诊断非法输入、Storybook 自身错误没有当前生产触发位置，明确按开发工具问题处理。

| 代号 | ZeroWork 证据 | 官方/参照依据 |
|---|---|---|
| P | [main.zig:129](../../src/app/main.zig#L129)、[macos_host_secret.m:137](../../src/platform/macos_host_secret.m#L137) | 原生窗口扩展；对应提交的 native input/window/drop 回归 |
| T | [build.zig:38](../../build.zig#L38)、[appearance_font.zig:251](../../src/config/appearance_font.zig#L251)、[layer_materials.zig:244](../../src/shared/ui/styles/layer_materials.zig#L244) | token 层、字体注册、窗口拓扑失效各自是公共设施 |
| Y | [spike/views.yix:16](../../tools/mockups/yix_spike/views.yix#L16)、`:34`、`:55`；[YIX_SPIKE.md:977](YIX_SPIKE.md#L977)、`:1067` | 官方 [VIEW_DSL:43](../../vendor/zenit/docs/VIEW_DSL.md#L43)；各提交的编译器最小用例 |
| S | [rows.yix:203](../../src/features/settings/view/components/rows.yix#L203)、`:217`、`:429`；[settings_window.yix:37](../../src/features/settings/view/settings_window.yix#L37) | Source/Model、parts、声明式焦点；`docs/skill/zenit-ui-components/SKILL.md:216` |
| G | [nav.yix:33](../../src/features/settings/view/nav.yix#L33)、[page.yix:39](../../src/features/settings/view/page.yix#L39)、[header.yix:37](../../src/features/settings/view/header.yix#L37) | 原生 GlassBox/ScrollArea/Toolbar；znote `znote/src/shell/chrome/compose.zig:75` |
| N | [toast_stack.yix:86](../../src/features/notifications/view/toast_stack.yix#L86)、`:150` | Notifier 自己管理卡片、暂停、布局和部件；官方 notification 测试 |
| O | [overlay_host.zig:41](../../src/shared/ui/overlay/overlay_host.zig#L41)、`:78`、`:249` | 官方 [Popover tests:2787](../../vendor/zenit/src/ui/components/popover/tests.zig#L2787)；原生焦点/浮层栈 |
| M | [app_menu.zig:162](../../src/features/shell/view/app_menu.zig#L162)、[session_menu.zig:130](../../src/features/workspace/view/session_menu.zig#L130) | 原生 Menu；内部 retained 生命周期测试 [Popover:2420](../../vendor/zenit/src/ui/components/popover/tests.zig#L2420) |
| K | [views.zig:2577](../../src/plugins/bmc_ikvm/views.zig#L2577)、[overlays.yix:41](../../src/plugins/bmc_ikvm/overlays.yix#L41) | 原生 Select/TooltipSurface；显式 scheme 与视频 HUD |
| F | [float_layer.zig:815](../../src/shared/ui/float_card/float_layer.zig#L815)、[workspace.zig:2985](../../src/features/workspace/view/workspace.zig#L2985) | 官方 [AnchorTransition:143](../../vendor/zenit/docs/ANCHOR_TRANSITION.md#L143) 及独立布局/快照回归 |
| L | [ai_launcher.yix:27](../../src/features/ai/pane/view/ai_launcher.yix#L27)、[launcher_view.zig:120](../../src/features/ai/pane/view/ai_launcher_view.zig#L120) | GlassButton props、内置动画；drag.Binding |
| C | [ai_composer.yix:29](../../src/features/ai/composer/view/ai_composer.yix#L29)、[controls.yix:128](../../src/features/ai/composer/view/ai_composer_controls.yix#L128)、`:221` | 公开 slots、Model、Ref、Slider/Progress 组件 |
| A | [ai_assistant_styles.zig:115](../../src/features/ai/pane/view/ai_assistant_styles.zig#L115)、[ai_message_view.zig:133](../../src/features/ai/pane/view/ai_message_view.zig#L133)、[tool_results_view.zig:363](../../src/features/ai/cards/view/ai_tool_results_view.zig#L363) | Markdown/CodeBlock 原生实现；[VIEW_DSL:81](../../vendor/zenit/docs/VIEW_DSL.md#L81) 的组件组合方式 |
| D | [data_cleanup.yix:30](../../src/features/settings/view/data_cleanup.yix#L30)、[confirm.zig:76](../../src/shared/ui/confirm/confirm.zig#L76) | Modal/ConfirmDialog；zeditor `zeditor-new/src/zdoc_app/save_prompt.zig:37` |
| H | [shortcut_text_consistency_native.ts:43](../../e2e/shortcut_text_consistency_native.ts#L43)、[REQUESTS:99](../human-feedback/REQUESTS.md#L99) | harness 的有界查询及结构化 paint facts |
| V | [ai_history_view.zig:21](../../src/features/ai/pane/view/ai_history_view.zig#L21) | [VirtualList:989](../../vendor/zenit/src/ui/components/virtual_list/mod.zig#L989)；支持组合不等于允许改内部生命周期 |

**A 类：101 条。** 表中“通用”是接口/行为判断，不代表应原样合入所有实现细节。

| 提交 | 改动与判断依据 |
|---|---|
| `523d53ac` | Select 部件/样式、Accordion 动效开关、VirtualList 位移开关、Input 状态样式：公开组合接口有通用价值；K/V。当前未找到 field_state_style 生产调用；Accordion 历史调用为 `ffd61ae7^:settings_accordion.zig:28`。 |
| `8d5fbf24` | 原生事件过滤、红绿灯布局：公共宿主能力；P。混含的 IME 键归属、新行文件名 drop 修复属于 B 性质。 |
| `a451c73e` | 选择当前 surface 采样，能支持离屏预览；[background_layers:232](../../src/features/shell/view/background_layers.zig#L232)。 |
| `f14fce94` | 窗口拓扑 revision，通用缓存失效；T。消费者复杂不使 revision 本身成为误用补丁。 |
| `34bd4b51` | 公共样式类型导出，减少内部 import；公共 API 设施，无单一生产触发点。 |
| `e9cadbf5` | 可变字体精确数值字重；T。 |
| `0da36bfc` | 角色 token、Checkbox 尺寸、Progress 状态/扫动：主题与组件能力；T/S。 |
| `c9c31d2e` | 基础主题加应用 overlay；T。 |
| `6bec4ee1` | Select fill 同时贯穿内部 wrapper；[appearance.yix:422](../../src/features/settings/view/panes/appearance.yix#L422)，仅改外层宽度不能替代。 |
| `b0dc251d` | switch 多值分支，常规语言能力；Y。 |
| `9de7251d` | Pressable 提供自定义内容与按钮语义；S，替代往 Button 内部追加内容。 |
| `c6f18375` | 手写组件与 Yix 的 Handler/Source props 转换；Y/S。 |
| `21a4a920` | parts 的 test_id 可由参数提供；S。 |
| `c23f63e8` | token gradient；[updates.yss:11](../../src/features/settings/view/panes/updates.yss#L11)，避免挂载时颜色快照。 |
| `a24c02cc` | Tooltip/Menu/Popover 模板触发器组合；S/C。 |
| `8d6bbb08` | Button Look 与主题/状态合并；Y，替代持续覆盖原生 paint。 |
| `e5dabbb3` | 捕获阶段按键与 composing 标识；S/C。 |
| `2573cddb` | 声明式焦点请求、恢复、目标登记；S。 |
| `4b3c8994` | ScrollArea 受控 offset；G，参照项目原先命令式保存/恢复不是同等模板接口。 |
| `7a86d8e2` | 普通值 props 从转发 Source 挂载期读取；Y/S。属于模板互操作扩展；不承诺动态跟随。 |
| `b0b8eec5` | GlassBox fill 贯穿正文 wrapper；G。 |
| `1d59785e` | TitlebarEdge 模板形式、ScrollArea 自有 scroll-edge；G。 |
| `7650b089` | GlassToolbar 模板子项与 disabled；G。 |
| `4149a47a` | focus-within 事件；S，普通 onFocus 不等价。 |
| `fc9312ab` | Button 尾随图标；[rows.yix:477](../../src/features/settings/view/components/rows.yix#L477)。 |
| `33b893de` | Kbd 键帽；S。 |
| `bc987260` | NotificationHost 模板入口；N。 |
| `94f9a1b3` | Modal 尺寸 Source 和固定高度；D，公开尺寸接口。 |
| `49e16cfe` | Modal body spacing；D，避免修改内部布局。 |
| `d47121b5` | 通知第三动作；N，协调器 `max_actions=3`。小型通用扩容，不足以判低价值定制。 |
| `ecf844cf` | 通知可展开详情；N。 |
| `00dbc96b` | 焦点在通知内暂停计时；N，键盘可操作性。 |
| `ab41e139` | 通知栈抑制但保留内容和计时；N。 |
| `adfc9d3e` | 通知/提示部件 test_id；N。 |
| `851b5593` | footer、life bar、详情框、host test_id；N。 |
| `9394142e` | 矮窗口收缩通知详情，动作保持可达；N。 |
| `93cabe3d` | 锚点动效几何和时钟；F。 |
| `b40ec3e5` | 快照任意仿射映射；F，独立于 ZeroWork 的渲染能力。 |
| `8b8a8b0c` | AnchorTransition 生命周期与快照入退场；F。 |
| `32069f7c` | 声明式 anchor 属性；F。 |
| `ed255366` | 动画 loops/yoyo、ping/breathe；L。 |
| `618754c8` | GlassButton 响应式 tint、ink、label、pulse、lift；L。 |
| `66fc8314` | scroll-edge hold 可配置；G，属于渐变曲线参数。 |
| `48d85afe` | GlassButton drag 与 click 互斥；L，常规手势仲裁。 |
| `7f60154b` | Menu 虚拟锚点，支持指针处上下文菜单；M。 |
| `889b73a8` | Menu 行与 panel test_id；M/H。 |
| `813bd80e` | 可选 fade-scale 动效模式；F。 |
| `d8e079ac` | anchorMotion 接受 Source；F。 |
| `7a20e21c` | Alert action test_id；K/A，消除内部节点探测。 |
| `6b448626` | inert 子树，键盘与 a11y 一致；O。 |
| `cf05307d` | Menu 图标 tint；设置颜色选择场景，原生 Menu 保持语义。 |
| `06e8da98` | 就地 TooltipSurface，视频 HUD；K。 |
| `4a1e2f29` | 就地 HintCapsule；K。 |
| `0795646a` | Card fill 贯穿内容；[float_chrome.yix:44](../../src/shared/ui/float_card/float_chrome.yix#L44)。 |
| `403abc35` | Tooltip trigger fill，避免包裹后破坏省略布局；S。 |
| `7db0b2e1` | 子树固定色系及对应 tokens；K，视频上方控件不应盲从窗口色系。 |
| `345ca609` | 快照自身节点矩形与阴影边界分离；F。 |
| `13b3630b` | Card floating 表面预设；F，非模态浮动表面是通用场景。 |
| `3302ce66` | Grabber 指示器；[float_chrome.yix](../../src/shared/ui/float_card/float_chrome.yix#L44)，行为仍由宿主管。 |
| `924abf67` | 可选 Input Esc 回退策略；O，默认不变。 |
| `46292469` | Empty 空状态组件；[ai_empty_view.zig:128](../../src/features/ai/sessions/view/ai_empty_view.zig#L128)。 |
| `d3641cf6` | Grabber active 可视状态及可配置宽度；F。 |
| `65094f5d` | 动画 restart 明确替换起点；[float_layer:663](../../src/shared/ui/float_card/float_layer.zig#L663)，与连续 retarget 不同。 |
| `07d860e2` | Menu heading 行及键盘跳过；M。 |
| `3f97f0c5` | disabled_reason 及 a11y 描述；M。 |
| `2da1eea6` | 子菜单 test_id、高度约束；M。 |
| `af37bb96` | Menu 色系并传递到子菜单；K/M。 |
| `27f55819` | harness paint facts；H，结构断言不能替代视觉事实。 |
| `775cacbc` | ConfirmDialog 预设；D。 |
| `34a64a51` | 通知被宿主移除的事件；N，undo 生命周期需要完整结束通知。 |
| `7d296b28` | ConfirmDialog 标题部件/ID；D。 |
| `51f2d934` | 确认框内异步步骤、禁用取消、重聚焦；D。 |
| `50f8a373` | slotted ConfirmDialog panel ID；D，portal 根不能用普通根 ID 替代。 |
| `6bf8bd41` | 缓存纹理 genie 网格合成；F。渲染原语可通用，后端覆盖仍有限。 |
| `1288b66b` | 快照 layer_parent，遵守窗口内部层叠；F。混含的布局 hook 同步属于 B 性质。 |
| `e7ede463` | Markdown code chrome、GFM table；A。 |
| `d5cb6b98` | Textarea header/footer compound field；C。 |
| `b21e555d` | Menu description/tag；C/M，丰富命令说明仍保留原生导航。 |
| `d92f9af9` | Disclosure 语义、状态槽、受控展开；A。左侧 rail 是样式选择，宜保持可组合。 |
| `d97a848c` | Alert actions/details slots；A。 |
| `d8c05c16` | AttachmentChip 行/缩略图形式；[ai_attachments_view:334](../../src/features/ai/attachments/view/ai_attachments_view.zig#L334)。 |
| `4dc009c3` | Card bubble 预设；[ai_user_message_view:28](../../src/features/ai/pane/view/ai_user_message_view.zig#L28)，聊天是常见应用场景。 |
| `aaf1e071` | Markdown heading sizes、table ID；A。 |
| `7a0fb08f` | 独立 CodeBlock，流式 code 原地更新；A。 |
| `216366fc` | Alert 部件 ID、本地化详情标签；A。 |
| `c670bf51` | Disclosure 部件 ID；A。 |
| `2c3d8f64` | Button dropdown chevron；C。 |
| `9600f8bc` | RadioOption description；[composer_interaction.yix:37](../../src/features/ai/composer/view/ai_composer_interaction.yix#L37) 所在提问面板。 |
| `56bf69f1` | Textarea auto_rows；C，组件自己掌握文字测量和 frame。 |
| `9bde0b9f` | Tabs segmented；C，已有 pill 不等于等分 segmented。 |
| `7009275f` | ProgressRing/Segments；C。 |
| `20cab022` | CodeBlock scroll Model；A，组件封装后仍须保留阅读位置。 |
| `8fc8724c` | 子树/可见树读取；H，保留。 |
| `03249126` | TabItem test_id；C，避免重建丢失调用方后写 ID。 |
| `f1c8b502` | wheel-transparent 节点；[float_layer:398](../../src/shared/ui/float_card/float_layer.zig#L398)，指针交互与滚轮路由可分别声明。 |
| `cf6d15b9` | 组件参数转发 Result Ref；C，避免宿主挖内部节点。 |
| `a5919c21` | Slider marks、thumb visibility、stepped look；C。前两项通用；stepped 外观可后续抽成 Look。 |
| `e77f9a82` | Button progress glyph；C，常见进度反馈；不应代替未来通用 leading slot 设计。 |
| `e7e8c9c6` | Pressable a11y_description；C，通用可访问性能力。 |
| `c7c79644` | Tooltip close_on_escape 可配置；C/O，允许明确指定被动说明不占 Esc。 |
| `377c85f5` | Textarea header_visible；C，显隐由组件拥有。 |

**B 类：67 条。** 其中至少 16 条修复本分支新增能力或其后续集成问题，不能全部宣传成“main 原有的 67 个 bug”。

| 提交 | 按官方用法也会触发的原因 |
|---|---|
| `8dc68167` | Select 打开时重建 options 丢键盘高亮；S/K，官方 Select 测试覆盖主题重建。 |
| `f18812f8` | 保留高亮后虚拟行未滚回可视区；S/K。 |
| `8c61d8fb` | 重绑虚拟行未重新画高亮/active-descendant；S/K。 |
| `c339486d` | 冻结 idle clock 后显式 redraw 未执行布局 hook；P/F，正常请求帧即可触发。 |
| `b3a7e891` | 原生 retained Menu 自己 detach 后，内部 Popover/Tooltip 不能重开；M，非应用 reparent 独有。 |
| `b6a4491b` | 多窗口主题过渡使用另一窗口时钟；P/S。 |
| `3b2a2309` | no_cross_stretch 错误压过显式 fill；G/S。 |
| `aede47d1` | 正常主题重放中，原生浮层 hook 改变 children 导致失效遍历；M/O。 |
| `6b78e0e0` | 动态文本更新后的 fit 测量使用旧换行；N/A/G。 |
| `f64cb4ff` | 原生 ScrollArea 隐藏 scrollbar 在主题重放后显色；G。 |
| `04eaa3c1` | 窗口时钟落后导致过渡停留起点；P/S。 |
| `51dfb3df` | handler 实参 initializer 的 `=` 被误识别为字段赋值；Y。 |
| `e6eb3ca4` | 模板边界 `//` 被渲染为文字；Y。 |
| `59cfb4f9` | 不平衡括号让编译器 panic；非法开发输入，无生产运行触发点；Y 诊断契约。 |
| `10968a5f` | 错把响应式源插值时输出结构体转储；Y。应用写法需改 `.get()`，编译器诊断仍应保留。 |
| `d140652e` | 合法大样式类型超过 helper 自身编译期 quota；Y。 |
| `c9fa9226` | 保留属性名作组件参数未在声明处诊断；非法开发输入；Y。 |
| `d9e15547` | recipe 维度中的 row 字段/调用未提升；Y/S。 |
| `28303cf9` | 原生 Input/Textarea 内部文字、caret 等不随主题更新；S/C。受控输入契约本身原已存在。 |
| `90c91733` | 列表协调前求值将被删除行，普通 `{for}` 可越界；Y/S，[scope.zig:1327](../../vendor/zenit/src/ui/reactive/scope.zig#L1327)。 |
| `92e8f8e1` | idle 后点击及命中刷新破坏动画时钟；S，普通 Switch 即可触发。 |
| `6c25655d` | parts/state/a11y 的表达式处理不一致；Y/S。 |
| `61b8bbf3` | 原生 Modal/Sheet 遮罩和面板保留挂载主题；D。 |
| `6a2039c6` | reverse 布局重复计算起始 padding；普通 padded reverse box 即触发，fc9312ab 暴露此问题。 |
| `6dc3345b` | 本分支 Toolbar 改动使官方 GlassAdapt story 不编译；无 ZeroWork 生产触发点。 |
| `701c042b` | mounted-open Modal/Sheet 未在 focus order 可用后聚焦；D。 |
| `12027fa1` | 已关闭 Modal/Sheet 的常驻内容进入 Tab 顺序；D。 |
| `4f95e20e` | builder Props 有 test_id 时，合法 Yix testId 无法到达组件；S/C。 |
| `f1400657` | 新增默认展开详情错误永久暂停通知；N，本分支能力后续修复。 |
| `9fb04885` | 通知长路径/hash 将文本列撑出卡片；N。 |
| `54935c3e` | 通知长 action label 撑出 footer；N。 |
| `e804139d` | 新 scroll-edge 在 strength=0 时仍均匀模糊；G。 |
| `a8d5a76a` | standalone Cx portal 自身命中遮住窗口区域；预览/测试路径，不是生产 portal 的 bug。 |
| `dacd005d` | 原生 Alert 长消息不能在既定宽度换行；K/A。 |
| `53167345` | Tooltip 抢先消费覆盖其上的 dialog 的 Esc；O/M。 |
| `30399f0f` | Model 写入回调卸载所有者后继续读已释放 source；D，条件挂载 Modal 是合法用法。 |
| `35430a45` | 新 fixed scheme 内原生控件仍解析窗口 tokens；K。 |
| `d9aa0a49` | AnchorTransition 把阴影 bounds 当节点 rect，造成几何偏移；F。 |
| `7dc8d336` | hit block 尺寸变化未更新后续 block；C/F，普通 reflow 即触发。 |
| `17a43a65` | 横向 ScrollArea 内容宽度被错误约束；附件条等普通横向布局即可触发。 |
| `05270fc7` | trap Popover 关闭归还焦点错误，并抢回外部新焦点；O。 |
| `5b8112bd` | 开着 Menu 时 Tab 离开菜单但菜单未关闭；M。具体 Tab 产品策略可讨论，不能让焦点无约束穿透。 |
| `eb09dc86` | opener 主动聚焦 panel 内控件后被组件覆盖；O。 |
| `9219cc6a` | 返回焦点未按 generation 跟踪，重建控件后 trap 丢焦点；O。 |
| `c904c902` | 前述恢复逻辑把用户主动 clearFocus 误当重建；O，属于修复系列中的纠偏。 |
| `55dbe36f` | 打开后立即重建时，焦点记录起点过晚；O。 |
| `2b46fb00` | 合法延迟挂载内容时，trap 未等待首个控件；O。30 帧常数仍宜审视。 |
| `b382b469` | trap 内焦点节点释放后没有回到有效 trap；O。 |
| `577f00e4` | 子树删除/stale handle 的同类失焦路径遗漏；O。 |
| `185d976d` | trap 自动恢复抢在命名焦点恢复之前；O/S。 |
| `ab8cb6fa` | Modal/Sheet 关闭期间错误覆盖用户已移走的焦点；D/O。 |
| `9882c96c` | 新 Esc 回退策略未把聚焦后应用写入值作为基准；S/O。 |
| `8e3c87d1` | 原生 Tooltip 留在后来打开的菜单/对话框之上；M/O，标准组件组合可触发。 |
| `f07c3958` | 原生 Menu 关闭期间重建 rows 后子菜单无法打开；M，组件自己失去 scope binding。 |
| `3afbb197` | 新静态快照模型的捕获、落地、时钟错误；F。 |
| `06f99549` | in-flow expand 的 home 重布局未刷新画面；F。 |
| `2a1c3413` | 过程初期 home 稳定时仍沿用不合适的 blend；F。 |
| `674c912c` | expand 捕获未同步普通 ScrollArea hook 几何；F，不要求应用手写滚动条。 |
| `cb7d87a7` | 冻结纹理被逐帧 command ID 变化反复重栅格；F，缓存 key 正确性。 |
| `59dbd744` | 新 expand 捕获早于虚拟内容/布局稳定；F/V。应用重度同步放大它，但普通异步测量组件也可触发。 |
| `3d86f7c5` | 忽略 home 亚像素变化导致落地纹素错位；F。 |
| `93ffe636` | 新 tree layer 插入位置违反 sibling stacking 顺序；F。 |
| `1b1245b6` | Markdown 有序列表丢句点；A。 |
| `b2be565b` | Markdown list/quote 长不可断词撑宽文档；A。 |
| `4e2b3012` | 新 CodeBlock 保留挂载主题；A。 |
| `733f64b4` | 新 AttachmentChip remove 覆盖缩略图中心，正常点图片变成移除；附件组件普通使用即可触发。 |
| `4aac7431` | Yix 组件重绑 Popover/Tooltip 根时清掉内部 liveness slot；C/M，合法组件封装同样触发。 |

随附项处理如下，避免遗漏或重复计数：

- `12477315`、`590f6ab5`：A 类公共文档打包。
- `29781f34`：A 类 Storybook 明暗主题检查设施。
- `e8b0dda8`：组件索引维护，随对应组件。
- `6801b378`：保留诊断测试；**没有修复框架行为**。G39 实际是 hover border，不是焦点未释放。
- `6828e96a`：恢复误改测试行，无独立运行时改动。
- `977d4690`、`de8caa9e`：随 AnchorTransition/genie 能力的示例。
- 85 个文档提交、8 个合并提交：随所描述/合并的主体，不再制造独立 A/B/C/D 条目。

另一个应明确保留的反例：review 中的 Switch 残留颜色报告没有获得框架复现；G26 又记录过 ZeroWork 按颜色反推角色、误把原生 Switch 的 accent 写入应用 inline 层。**这类应用重映射错误应改应用，不能继续要求框架猜测颜色所有权。**

---

**分批整改与上游撤除顺序**

| 批次 | 先改 ZeroWork | 后处理上游 | 依赖、规模与风险 |
|---|---|---|---|
| 1 契约修正 | VirtualList 改 `mountScoped`；明确列表适配器所有权；停止通过 test_id 找气泡内部列 | 不撤 A/B | 小到中；可与标题栏迁移、材质盘点并行。关注列表单独释放、回收、父 Scope 释放。 |
| 2 消除双重写入 | 原生组件 props/parts 接管排版、尺寸、显隐；删除 BMC 排版重刷、背景“写回再清除”；统一 hover/Esc 来源 | `9e3720cc` 已无应用调用，可先剥离；其余保持 | 中；按 feature 并行，避免多人改全局主题模块。关注主题、disabled、键盘/指针切换。 |
| 3 标题栏迁移 | 扩展 AuxWindow Spec；迁移 process_windows/main 的 chrome；确认 native controls、drag/client 区域 | 再撤 `c48c9de4` | 中；不依赖内容重构。需覆盖主窗、设置窗、插件窗及窗口控制区。 |
| 4 材质局部化 | Menu/Popover/Modal 恢复自身材质；KVM 显式声明可读性；逐步替代全局补偿遍历 | 不撤 `a451c73e`、`f14fce94` 等通用能力；只清理失去消费者的应用逻辑 | 大；先做创建者明确的表面。视觉风险高，可与非材质业务重构并行。 |
| 5 生命周期收敛 | 业务状态与展示树分离；集中 reparent 协议；重型 UI 按需挂载；transition 只有一个所有者 | 此前不能撤静态模型的身份、布局、缓存修复 | 大；依赖批次1，建议在批次2后展开。风险最高。 |
| 6 动效策略剥离 | 应用显式定义 shape/hold/easing/duration；统一落地 hover；安排焦点外观与捕获时机 | 分别剥离 `ca5fddf7`、`9b7fb6cb`、`b8fbce3c`、`60795a62` 的默认策略；保留通用计算与 B 修复 | 依赖批次2、5。不能按提交逆序 wholesale revert；后续修复已依赖这些结构。 |

后续实施时需要验证的重点是：IME 中开关面板、拖动中关闭所属 tab、嵌套浮层重建、焦点移到外部后退出、停靠与浮动之间的滚动/选区恢复、双窗口主题切换。此次没有执行这些验证。

**对用户判断的最终评价**

用户的判断在**应用层设计问题**上相当成立：全局材质重写、按颜色识别角色、生产 test_id 查询、组件内部状态改写、重复 hover/Esc 和跨宿主节点协议，都有明确证据。其中焦点填色、primary token 覆盖等问题还已经由 ZeroWork 自己整改过。

但在**这批上游补丁的总体归因**上，判断过强。按本次主类计数，C/D 为 6/174；大量 B 可由原生组件及合法 Source/Model 用法触发，A 中还有不少能力恰恰用于消除应用挖内部节点的做法。参照项目也存在类似旧写法，且 zeditor 当前依赖 `zenit-release-head`，不能把其问题数量直接当作相同版本下的对照实验。

最该优先做的五件事：

1. **修 AI 历史列表的 Scope 契约，封装虚拟化适配器。**
2. **停止宿主寻找、改写组件内部结构，尤其气泡宽度与 BMC 控件排版。**
3. **把全局材质策略改为创建者声明，消除多个属性写入者。**
4. **统一 hover、Esc、焦点裁决，删除与原生浮层重叠的路径。**
5. **收敛 retained reparent 与 AnchorTransition 生命周期，再剥离产品动效默认策略。**
---
## 用户拍板（2026-11-15）
按 1–6 批全部整改。先改 ZeroWork 的用法，再撤掉对应的 C/D 类上游默认策略；不整提交回滚。批次 1–3 并行，4、5 在 2 之后，6 在 2 和 5 之后。每批都按"要快"的门禁执行：空窗口黑盒验证，加上本批相关的 e2e。
