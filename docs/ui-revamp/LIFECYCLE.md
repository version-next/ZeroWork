# 生命周期契约（zenit 用法整改 批次 5）

本文是 ZeroWork 里“内容在哪显示、谁拥有它、什么时候能动它”的契约。代码以这里为准；改动契约先改本文。
每节末尾的“状态”如实记录已实施到哪一步。

## 1. 状态归属表

| 状态 | 归属（唯一来源） | 展示树里的东西 | 展示树消失后怎么回来 |
|---|---|---|---|
| 终端会话（PTY / SSH 通道、回滚缓冲、选区、IME） | `SessionTab`（`terminal`、`runtime`） | 终端表面节点 `SessionTab.root`（**保留表面**，带原生资源） | 不消失：只经 §2 迁移 |
| AI 对话（消息、回合、流式输出、执行队列） | `assistant_store` 的 conversation + `AiHost.execution()` | AI 内容视图 `AiHost.content_node`（显示期间是**保留表面**：停靠 ↔ 浮动只经 §2 迁移，不重建） | 面板关闭且外框静止后释放；再打开时从模型重建（§3） |
| AI 草稿 | `assistant_store` state 的 `draft`（切换会话 / 所有者时由 `persistDisplayedDraft` 写入） | 输入框是受控 `W.Textarea`（值来自 `AiHost.prompt` 信号） | 从模型恢复 |
| AI 对话滚动位置（含是否贴底跟随）、消息文本选区、输入框与编辑中气泡的光标、键盘在哪 | 显示期间在节点里（ScrollArea 状态、`ai_text_selection`、Textarea 状态）；视图离开前由 `AiHost.captureViewState` 取进模型 `AiHost.view_state`（选区用 `ai_text_selection.Saved`：根的路径 + 范围 + 文本哈希） | 同上 | 停靠 ↔ 浮动：节点不销毁，原样保留（§2）；关闭 → 再打开、对话整段重建：从 `view_state` 还原（§3）；换了会话则丢弃 |
| 卡片位置 / 大小 / 是否最大化 | `float_model.Placement`（每个卡片主人一份） | 浮动外框节点 | 外框常驻，位置来自模型 |
| 卡片在哪显示（浮动 / 停靠在哪个 tab 的分屏 / 关闭） | 主人的模型：AI 是 `controller.model.{visible, docked_leaf}` + `display_owner`；会话卡片是 `SessionTab.floating` + roster | —— | 由 §2、§4 按模型摆放 |
| 分屏结构 | `group_view.View.tree`（+ `sizing` 存盘） | 窗格与分隔条（**轻量 UI**，每次呈现重建） | 重建 |
| 窗格头部、外框头部、菜单、Tooltip、弹层 | 各自的 view-model 信号 | 轻量 UI，跟随目的地 Scope 挂载 | 重建 |
| 设置窗口内容 | `SettingsController` + 配置 | 独立窗口，按需创建 | 重建 |

规则：**轻量 UI 在目的地重新渲染，不靠搬节点保状态；只有上表标“保留表面”的节点可以换宿主，而且只能走 §2。**

**AI 显示在哪属于所属 tab，不属于它此刻显示的对话。** `float_model.Model` 里的 `visible`、`expanded`、
`placement`、`docked_leaf`（`Model.OwnerPresentation`）是 tab 的：tab 换对话（会话列表里恢复、新建、使用副本）
时由 `AiHost.syncOwner` 原样交给新对话，离开的对话一样也不带走（尤其不带走停靠的
分屏叶子）。所以停靠在分屏里换对话时，窗格留在原处、显示新的当前对话，浮动面板不出现；之后窗格的“浮动”照常把它
浮回。定位到别的 tab 的对话是换 tab：切到那个 tab，按那个 tab 自己的形态显示（那里是浮动就浮动）；回到停靠的 tab，
窗格里仍是这个 tab 自己的对话。查看历史只开历史对话框，不改形态。测试：e2e `ai_dock_sessions_native`（停靠时
定位 / 查看历史 / 恢复 / 使用副本 / 新建）、`float_model.zig` 单测。

## 2. 表面迁移适配器（`src/shared/ui/surface/surface_migration.zig`）

保留表面换宿主的唯一入口。Workspace、AiHost、会话浮动卡片宿主、测试卡片宿主都调它；生产代码里不再有
`detachChildRetained` + `appendChild` 的手写搬运，也不再有搬完之后各自修焦点 / 过渡 / 身份的代码。

`move(cx, surface, host)` —— 目的地在窗口树里，一次调用内按顺序完成：

1. **关浮层**：从表面子树里打开的 Popover / Menu / Tooltip 及其子菜单请求关闭（上游 `Cx.dismissOverlaysFrom`）。
2. **清与旧位置绑定的输入**：悬停、按下、指针捕获、进行中的拖动、滚轮会话与惯性。
3. **迁移**：上游 `Cx.moveChildRetained`，节点一步换到新宿主，期间不算被移除。
4. **属于节点的状态原样保留**（不是“事后恢复”，是从未丢失）：键盘焦点（不发 blur / focus）、原生输入会话
   （IME 组字继续）、文本选区、滚动位置、Scope / hook / 资源、节点身份（AnchorTransition、浮层触发点、拖动绑定
   在迁移前取得的 handle 继续有效）。

`park(cx, surface)` —— 表面离开窗口（所属面板关闭后静止、所属 tab 关闭、宿主销毁）。这是真的移除：焦点离开
（发 blur），身份作废；节点、Scope、资源保留。停放期间错过的主题切换在下次 `move` 放回时补一次重放。

调用方的义务：

- **先挂宿主，再迁内容。** 目的地不在窗口树里时，`move` 把焦点按移除处理。分屏重建（`Workspace.presentGroup`）
  的顺序是：新窗格挂进窗口 → 各表面从旧窗格一步迁到新窗格 → 拆旧窗格。停靠时内容留在浮动外框里，直到窗格建好。
- **适配器不决定谁拿焦点。** 焦点没离开表面就没有人需要“放回去”；宿主用 `holdsFocus` 判断，只在表面本来不持有
  键盘时按自己的规则放（例如浮回后 AI 输入框取焦点）。
- **放置动作的按钮不取焦点**（`placementButton`）：放入分屏、浮动、作为标签页打开、最大化、最小化只改变表面在哪显示，用
  指针按它们时键盘焦点留在正文里（选区、编辑中的输入框不失焦）；键盘激活照常。
- **标签页“被用户激活”与“形态被恢复”分开**（`Workspace.TabFocus`）：只有前者把键盘交给标签页内容；为停靠而建的
  分屏解散、回到单卡片标签页属于后者，键盘留在刚浮回去的卡片里。

状态：已实施。上游：`Cx.moveChildRetained`、`Cx.dismissOverlaysFrom`（分支 `zw/usage-b5-lifecycle`）。
测试：`surface_migration_tests.zig`（焦点 / 光标 / IME / 滚动 / 身份 / 浮层 / 指针状态 / 过渡 / 放置按钮）、
`workspace.zig` 的 float-split / cards-float 单测、e2e `ai_dock_float_selection_native`。

## 3. 按需挂载

- **AI 面板**：浮动外框（`float_chrome`：头部、空 body、关闭确认）常驻在浮动层里，关闭时 `display: none`。
  **内容视图**（对话视口、虚拟历史、输入区、排队区、附件栏、两个头部弹层）是按需挂载的视图，有自己的
  Scope（`AiHost.view_scope`，宿主 Scope 的子 Scope）：
  - 需要时挂载：`AiHost.placeContent` 是唯一决定处——停靠、显示中、或外框还在飞行（收起要取它的画面）时
    需要；没挂就 `mountContent`（建节点与 Scope，计入 `lifecycle_budget.content_mounts` 与耗时），然后放到
    该在的位置：停靠 → 所在窗格；浮动 → 外框 body。打开时内容在同一步里挂好、放好，输入框随即取得焦点。
  - 不需要时释放：面板关闭、外框落地静止（`Card.phase() == .collapsed`）后，在帧 hook 的安全点
    `releaseClosedContent` → `unmountContent`：先 `captureViewState`（若关闭时还没取），清掉指向内容的指针
    捕获 / 焦点 / 浮层，再释放 Scope（effect、hook、弹层、组件状态）与节点，最后 `forgetContent` 清空宿主里
    所有指向视图的引用和“上次画了什么”的缓存。输入回调里从不释放（回调可能正来自将被释放的节点）。
    远端文件选择器还有列目录请求在途时等它排空。
  - 释放后宿主照常运行：模型、执行、后台任务（流式回合、终端执行、队列、标题、附件读取）不依赖视图。
    宿主里写视图的步骤在视图为空时跳过；它们的模型部分（草稿落盘、压缩提交、模型发现、审批通知等）
    不跳过（§5 的“模型阶段”不看视图是否存在）。
  - 读者状态：关闭开始时（`collapse` 第一步，键盘和选区还在读者手里）`captureViewState` 把滚动位置与是否
    贴底、选区、输入框与编辑中气泡的光标、键盘在哪取进 `view_state`；再打开挂载后，对话重建并布局完一轮，
    `stepViewRestore` 分两步还原：先滚动位置（虚拟历史要按这个位置再布局一轮才有那几行），再光标、选区、
    焦点。还原只给同一个会话；换了会话丢弃。选区按“根的路径 + 范围 + 文本哈希”还原，文本变了就不还原，
    绝不挪到别的文字上。贴底跟随是模式不是位置，在第一轮布局前设好，避免跳到读者已经离开的末尾。
  - 对话整段重建（换会话以外的原因：主题、配置、编辑开始 / 结束、回合结束）同样先取后还：选区、编辑中气泡
    的光标与焦点在 `rebuildConversation` 前后保留。
  - 排队编辑（哪条在编辑、编辑中的文字、队列折叠）是读者状态：主面板放在宿主 Scope 的
    `ai_pending_view.Edit` 里，视图每次挂载都接到同一份上（`View.mountOn`）。
  - 预算：关闭静止时 AI 相关的节点、Scope、hook 回落到“从未打开过”的水平（只剩外框）；外框保留的理由是
    过渡身份稳定（§4：`AnchorTransition` 随外框挂一次，打开从启动器展开要取外框的画面），实测节点数见 §6。
    停靠 ↔ 浮动 0 次对话重建；关闭 0 次；再打开 1 次（新视图的首次构建），耗时见 §6。
- **设置**：独立窗口，按需创建，关闭即释放；主窗口里只有一个隐藏的占位节点。
- **连接编辑器 / 插件窗口**：独立窗口，按需创建。
- **子代理对话框**（`child_dialog.zig`）：对话框本身按需创建，它的宿主与视图同生共死（宿主 Scope 即视图
  Scope），不走上面的挂载 / 释放。
- 普通确认框、菜单：原生组件常驻（关闭时不在浮层栈里）。

`retained_panel.zig`（隐藏面板脱树、重新登记 identity、`keep_attached`、`focusWhenAttached` / `focusPending`、
主题补放）已删除；浮动卡片焦点协议里的“主人的请求还在路上”（`CardFocus.Owner`）随之删除。AI 内容不再
`surface_migration.park`（停放只剩“所属 tab 关闭、宿主销毁”等仍需保留节点的表面）。

状态：已实施（usage-b5e-ai-host）。测试：e2e `lifecycle_budget_native`（关闭后节点 / Scope / hook 回落、
挂载次数与耗时、重建次数）、`ai_dock_float_selection_native`（停靠 / 浮动 / 关闭再打开后滚动、选区、光标、焦点）。

## 4. 过渡（AnchorTransition）只有一个拥有者

- 浮动卡片的过渡归 `float_layer.Card`：卡片挂载时用官方入口 `AnchorTransition.attach(scope, …)` 建一次，随卡片的
  Scope 释放。卡片节点从不离开浮动层，所以过渡不会因为身份变化而被销毁重建。
- 业务层只传三样：**展示状态**（`Presentation.shown` / `explicit` / `swapped`）、**锚点**（`anchor` 矩形或 tab）、
  **模式**（`FloatLayer.currentMode()`，token 由 `float_card_motion.tokens(mode)` / `placeTokens(mode)` 给出——
  批次 6 把 shape / hold / easing / duration 改为应用显式声明时只改这一个文件）。
- 业务层不读、不写卡片节点的 `display`，不拿 `display: none` 推断“业务上已关闭”；是否关闭只看模型
  （`presentedNow()`），是否静止只问卡片（`Card.phase()`）。
- 停靠窗格、放回标签页的飞入过渡归 Workspace 当次呈现的 Scope（`mountCardPanes` / `presentGroup` / `flyIntoTab`），
  同样用 `attach`。

**何时允许发起过渡 / 取图**（契约）：过渡的起点是上一帧的画面（收起）或本帧布局后的画面（展开）。因此
“改树”和“发起过渡”不能在同一个 after-layout 回调里先后发生——改树之后的树还没有布局和绘制，上一帧的显示列表
也可能引用已被这次改树释放的内容。规则：

1. 展示状态只在**提交点**交给卡片：`AiHost.updatePresentation` 是帧 hook（`PollHook.run`）的第一步，排在本帧
   所有会改对话树的步骤（会话动作、重建对话、流式刷新）之前。收起取的是刚显示过的那一帧画面；在这里提交，
   这幅画面对应的树还没有被本帧的重建动过。
2. 输入回调、异步结果、帧 hook 里靠后的步骤只改模型并调 `requestPresentation`（请求一帧）；它们改出的状态在
   **下一帧开头**提交，那时这些改动已经布局并绘制过。除提交点外没有任何代码调用 `Card.present`。
3. 停靠 / 浮回（`dockNow` / `undockNow`）只发起展开（取图在布局之后，由 zenit 在过渡自己的 hook 里完成）和无动画
   的隐藏（`hideForDock`），不取上一帧画面。

状态：已实施（单一拥有者、attach、不再重建、提交点）。剩余风险（不在应用侧）：输入回调在两帧之间同步改了卡片
里某个节点的文本（例如在输入框里打字）之后、下一帧提交点收起时，zenit 的 `Snapshot.captureDisplayed` 仍然从上一帧
的显示列表复制文本——这是上游快照借用已释放内存的问题，由 `usage-snapshot-uaf` 包修；应用侧没有、也不应该为它
加规避。

## 5. 逐帧工作：AI 宿主帧 hook 的触发

`AiHost.PollHook`（主面板宿主一个；每个子代理对话框的宿主一个）仍是一个 after-layout hook，因为它同时是
三样东西：§4 的展示提交点；会改对话树的步骤唯一的安全点（输入回调里不改树、不释放视图）；读布局结果的地方。
拆分的是**触发**：每类输入有自己的发布者，hook 每帧只做 O(1) 的比较；没有输入变化时一步业务都不跑。
步骤的相对顺序不变（“展示状态提交点先于本帧改对话树”的契约照旧）。

### 5.1 输入 → 发布者 → hook 里的门

| 输入类 | 发布者（谁写、在哪发布） | hook 里的门 | 打开后跑什么 |
|---|---|---|---|
| 工作线程结果 | `ai/publication.zig`：工作线程写完共享数据后 `publication.publish(wake)`——进程级修订号原子加一，并按 `Wake` 绑定的窗口 `presentation_wakeup.notifyTarget`（未绑定 = 唤醒所有窗口，可靠不静默）。`Wake` 挂在执行宿主（后端 `AiHost`）上，绑定到显示它的窗口。发布点见 5.3 | 宿主上次看到的修订号 ≠ 当前 | 宿主轮 |
| 环境（页签、分组、绑定、能力、重连、策略配置、输入租约、页签标题） | `host/environment.zig`：写入点在值真的变了之后调 `environment.publish()`（任何线程；修订号原子加一并唤醒所有窗口——这些是进程级事实，变化是用户尺度的事件）。写入点见 5.3 | 上次看到的环境修订号 ≠ 当前 | 宿主轮 |
| 本地请求（视图回调、键盘命令、Workspace 调进来的公开入口） | 宿主自己：`AiHost.wake()`（记一个请求位并请求一帧）。视图回调与外部入口 `defer self.wake()`；投到 AI 内容视图里的输入（按下、松开、点击、按键、文字、拖放；不含移动、悬停、滚动、焦点）由内容节点的捕获处理请求一轮——内容里的视图模型（决策卡的“稍后处理”、步骤折叠、队列行）不经宿主就会改宿主轮读的东西；`requestPresentation`、`refresh` 也走它 | 请求位 | 宿主轮 |
| 草稿、视图里读者自己能改的开关 | `prompt` 信号，以及会话列表 / 子智能体弹层、历史对话框、子代理对话框的 `open` 信号上的 effect（`AiHost.wakeOnChange`：Esc、点外部关闭不经宿主回调） | 同“本地请求” | 宿主轮（草稿落盘、发送按钮状态、释放关闭的对话框） |
| 宿主轮自己请求了下一帧 | 一轮跑完时若有人请求过重画（后面的步骤改了前面步骤读的东西、它更新的视图要重画——旧的逐帧循环下一帧会全部重跑） | `Gate.rerun` | 下一帧再跑一轮（没有新变化就停） |
| 时间 | 需要“到点再来”的步骤登记截止时刻 `AiHost.wakeAt(ns)`（取最早；同时 `scheduleRedrawAfterNs` 到那一刻）：持久化失败的 5 s 重试、资源释放重试（会话动作 / 关闭窗口 / 执行关闭 / 分叉在资源未释放时）、恢复冷却秒数、启动器 ping、模型发现的下次刷新、完成通知被拒后的重试、自动化租约的 10 分钟上限、图片观察的重试与截止、任务收尾卡片的结算；以及没有完成信号、只能看快照的原生执行：工具适配器里在途的本地 / SSH 命令、SFTP 读取、终端文件任务（适配器 `busy()` 或工具桥有工作线程侧的原生调用在途时 16 ms），远端读图（SSH 执行快照，16 ms），原生密钥收集框（16 ms），远端文件选择器排空（33 ms）——都只在在途期间有 | 截止时刻已到 | 宿主轮 |
| 主题 | 窗口主题发布 → `theme_watch.ThemeWatch`（与 b4 同形） | `take()` | 宿主轮（`refresh` 重画对话） |
| 配置 | `runtime_config` 的 `config_revision` | 修订号比较 | 宿主轮 |
| 跨窗口共享展示（会话相位、标题、是否列出、结束、所有者、绑定修订） | 共享 pump（`attached_service.Host.pump`）结束时比较 presentations 的指纹，变了 → `publication.publishAll()`（修订号加一并唤醒所有窗口） | 同“工作线程结果” | 宿主轮 |
| 布局（终端区 / 停靠窗格 / 内容 / 输入区的矩形） | zenit 布局结果 | 内容视图在，且矩形与上次不同或本帧改过树 | 布局步骤 |
| 逐帧（保留） | 流式输出在途（`thread_state == 1`）、贴底滑动、外框飞行（`Card.phase()` 非静止）、启动器 ping 动画 | 各自的状态 | 逐帧步骤 |

“宿主轮”就是原来的整串步骤（去掉死步骤 #25），顺序不变；一帧里任何一个门打开就跑一遍。安全检查因此和拆分前
在同一处、以同样的代码运行——只是触发从“每帧”变成“它的任何一个输入可能变了的那一帧”。

### 5.2 安全语义（拆分后不延迟、不丢失）

| 语义 | 代码 | 输入 | 由谁触发宿主轮 |
|---|---|---|---|
| 资源戳变化 → 结束会话 / 换环境、撤销路由选择 | `pumpAttached` 的 `resourceStamp` | 所属页签与分组、分组成员修订、会话所在页签、SSH 重连快照 | 环境修订号（Workspace 页签增删 / closing / content_owner，roster 成员变更，重连快照由 SSH 工作线程 `bumpFromWorker`） |
| 宿主上下文失效 → 撤销三个 broker 的待批 | `validateHostContext`（宿主轮里对显示中的执行宿主，`pumpAttached` 里对每个执行宿主——后台会话的待批同样撤销） | 请求上下文、绑定、`agentPolicyRevision`、会话 closed / ended / owner / binding_revision、record.transition、所有者解析 | 环境修订号（配置保存、绑定变化、页签）+ 工作线程结果（请求上下文、record 变化都在共享 pump 里发生） |
| 自动化授权失效 → 释放租约 | `ai_tools.Bridge.pump` 的 `releaseAutomation` | stopped、成员授权（绑定、句柄、roster）、能力修订、策略修订、待定绑定、`proof.valid()`（租约：失焦、换 owner、窗口转移、到期） | 环境修订号（会话能力 / 绑定、roster、策略、输入租约的每个撤销点）+ 截止时刻（租约到期）+ 工作线程结果（stopped） |

每条都有单测证明“输入变了的那一帧宿主轮就跑”（见 5.5）。

### 5.3 发布点

工作线程 → UI（`publication.publish(wake)`，`wake` 绑定显示它的窗口）：runner 线程结束（`Runner.run` 写 `state`
之后，`Backend.wake`）、流式 / 思考 / 重置、步骤、上下文用量三个邮箱的每次写入、工具桥与执行桥的四个投递点
（controller、host_exchange、controller_task、pending）及其撤回、工作线程侧原生调用的进出、自动化运行结束、
提问 broker 的 begin / finish、审批 broker 的 beginSubject / finish、执行驱动的 evidence 变化、work 由无到有 / 由有到无、
驱动结束；视图自己的服务（会话标题、模型发现、上下文压缩）任务完成。没有窗口归属的用 `publishAll`（唤醒所有窗口）：
附件 / 图片读取完成（读取器启动时还没有窗口）、日志检查点写完、inbox 的 work_phase 与消费回执（进程级 store）。
UI 线程上改了宿主要处理的状态：视图回调与外部入口 `defer self.wake()`；宿主内部原来的 `requestRedraw` /
`requestPresentation` 一律变成 `wake()`（“下一帧再跑一轮”的语义不变）。
环境（`environment.publish`，只在值真的变了时）：Workspace 的当前页签 / 当前分组、页签增删、`closing`、`content_owner`、
`plugin_renderer`、`runtime`、`floating` / `owned_pending`、分组视图与其停靠卡片的增删改、页签标题；workspace_model 的
页签增删、所有者 / 容器、当前与最近顺序、改名；roster 成员变更（含 `setActive`）；配置提交（任何字段变化）；SessionHost
的状态与能力修订、ApplicationHost 的映射增删与输入交还；SSH 重连控制的每次状态转换（两个线程）；输入租约的授予与撤销。
（逐条位置见代码里 `publication.publish` / `publishAll` / `environment.publish` 的调用点；新增写入点必须同时发布。）

### 5.4 跨窗口与子代理对话框

- 共享服务是进程级的：任何一个窗口的宿主轮都 pump 全部窗口的桥（与拆分前相同）。发布者唤醒的是显示该
  会话的窗口；别的窗口要看的共享展示状态变了，由共享 pump 的指纹比较 `publishAll` 唤醒所有窗口。
- 子代理对话框的宿主注册同一个 hook、用同样的门；它的视图与对话框同生共死。主宿主与子宿主共用进程级修订号，
  各自记“上次看到的”。`consumeInputHandoffs` 仍是窗口级队列（谁先跑谁取走），行为与拆分前相同。
- 不在帧 hook 里的（usage-b5f 合入后）：子对话框的 test_id 由挂载处的 `IdSpace` 决定（不再逐帧整树改前缀 / reflow）；
  会话阶段与已绑定数由 store 发布（`assistant_store.setPhase` → `SessionPhases`，`session_lifecycle` → `BoundSessions`），
  行与按钮角标订阅。订阅属于挂载它的 Scope：主面板的在内容视图的 Scope 里，随内容视图挂载建立（共享服务已绑定时在
  `mountContent` 里 `follow`）、随释放撤销；子对话框有自己的阶段板，属于对话框的 Scope，不引用父面板可能已释放的内容视图。

### 5.5 预算与测试

- 计数（`lifecycle_budget.counters`，诊断 `POST /zerowork/lifecycle` 读出）：AI hook 运行次数、宿主轮次数、
  宿主轮里执行的步骤数、每个门打开的次数。e2e `lifecycle_budget_native` 断言：各静止状态（AI 从未打开、打开、
  停靠、浮回、关闭）两秒内宿主轮 0 次。拆分前每次 hook 运行都执行全部步骤。
  “静止”由条件决定，不是固定等一段时间：外框不在飞（动画探针 `ai.panel.motion.phase` 不是 expanding / collapsing），
  没有任何 AI 帧 hook 会在下一帧跑宿主轮——每个 hook 向 `lifecycle_budget` 登记静止探针，用自己的门回答（有未处理的
  发布 / 环境变化 / 重跑请求、外框在飞），且没有落在接下来测量窗口内的截止时刻（模型列表几分钟后的下次刷新这类远处的
  截止时刻不必等，近的等它过去）；诊断 `ai_hooks` 逐个报告门的原因与截止时刻。测量窗口里只要窗口收到
  任何输入事件（`Cx.input_epoch`：激活 / 失活、指针、键盘、滚动、尺寸、系统主题——都是 AI 宿主的合法输入），这个窗口
  就无效、重新测（每个状态最多 3 个窗口）；全部无效才失败，并报告每个窗口的输入数。“静止 0 宿主轮”的断言本身不放宽。
- 单测：门的判定（每类输入单独变化都打开、都不变不打开、截止时刻）；每个发布者确实发布（Workspace 关页签 /
  切页签 / 加页签、roster 成员变更、配置保存、租约撤销、SSH 重连快照 → 环境修订号；broker begin、桥投递、
  runner 结束、邮箱投递 → 修订号与按窗口唤醒）。
- hook 范围：after-layout hook 在 zenit 里没有范围声明（`.subtree` / `.dirty_marking` 只用于 before-render
  hook）；宿主轮写的是它自己的视图（对话树、输入区样式、滚动位置）与模型，不声明任何“可缓存”的 before-render hook。

状态：已实施（usage-b5e-ai-host）。死步骤 `updateInventoryGrant`（#25，`inventory_view` 全仓库无赋值）已删除。e2e `ai_authority_at_rest_native`（亮 / 暗）：等待审批时宿主轮 0、不轮询提供方；关闭会话所在页签后待批立即撤回、命令不进 PTY，撤回由事件触发。

## 6. 预算

诊断接口（只在 test-mode 构建里）：`POST /zerowork/lifecycle` → 每个窗口的节点数（整棵树、弹层 portal、根下各
区域、标签页正文、停放在窗口外的表面）、after-layout hook 数、Scope 数、帧计数；进程级计数：对话整段重建、分屏
整体呈现、表面迁移 / 停放、AI 内容视图挂载 / 释放与最近一次挂载耗时、AI 帧 hook 的运行次数 / 宿主轮次数与布局轮数 /
各门打开次数 / 无宿主轮时的逐帧步骤数 / 两类运行的累计耗时（`shared/ui/surface/lifecycle_budget.zig`）。回归断言：e2e
`lifecycle_budget_native`（亮 / 暗），上限 = 下表“整改后”实测值 + 约 10%。

主窗口 1440×1000、一个本地终端标签页、AI 载入 12 回合的历史对话（usage-b5e-ai-host 实测，亮暗相同；“前”= b5-lifecycle
合入后的 `revamp/usage-integ` bb6ef863，见本节旧表）：

| 状态 | 窗口树节点 前 → 后 | after-layout hook 前 → 后 | Scope 前 → 后 | 静止 2 秒：AI hook 运行 / 宿主轮 / 逐帧步骤（后） |
|---|---|---|---|---|
| 壳 + 一个终端，AI 未打开过 | 2075 → 1946 | 66 → 51 | 2536 → 1897 | 5 / 0 / 0 |
| AI 打开（浮动） | 3393 → 3393 | 100 → 67 | 3208 → 3209 | 1 / 0 / 0 |
| AI 停靠进分屏 | 3477 → 3477 | 100 → 67 | 3371 → 3372 | 5 / 0 / 0 |
| AI 浮回 | 3394 → 3394 | 100 → 67 | 3208 → 3209 | 5 / 0 / 0 |
| AI 关闭（静止） | 2076 → 1947 | 100 → 51 | 3208 → 1897 | 5 / 0 / 0 |
| AI 再次打开 | 3394 → 3394 | 100 → 67 | 3208 → 3209 | 5–8 / 0 / 0 |

读法与结论：

- 关闭后回落到“从未打开过”的水平（1947 / 51 / 1897 对 1946 / 51 / 1897）：内容视图连同它的 Scope、hook 已释放；剩下的
  是空外框（约 105 个 `display: none` 节点：头部按钮与它们的 Tooltip、关闭确认），为过渡身份稳定而保留（§3、§4）。
  “前”的 AI 未打开状态里内容视图已经挂着并停放在窗口外（514 节点、15 个 hook），现在不存在。
- 停靠、浮回 0 次对话重建；关闭 0 次；再打开挂载 1 次、重建 1 次，挂载约 14 ms（300 回合虚拟历史约 14–15 ms）。
- 静止每帧工作量：拆分前每次 AI hook 运行都是一整轮（50 多步）；拆分后静止的每次运行只做门的比较。实测（同一构建）
  跑宿主轮的运行平均约 270 µs/次（含对话重建等重的轮），没有宿主轮的运行约 3.8 µs/次。
- 弹层 portal 常驻约 1274 个节点、窗口 Scope 1800+：与本包无关的既有成本，记录在案，未处理。
- 按功能细分只做到“主窗口壳 / 终端标签页正文 / AI 面板”三项；设置窗口、KVM、文件 / 传输没有测量。

状态：诊断接口与回归断言已实施；按功能的完整表未完成。
