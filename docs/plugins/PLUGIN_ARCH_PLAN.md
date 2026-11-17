# ZeroWork 插件化技术方案

> 状态：设计稿。已经过 GLM 交叉评审（评审对象是较早的版本 `40480549`），逐条处理结果见 6.5；Q1–Q12、Q5a–Q5c、Q14–Q17、Q20、Q21、浮动放置（第四批）、AI 能力归属卡片（第六批）与 AI 入口改为每个 tab 的浮动图标（第七批）已判定，Q22–Q24（第八批）已判定，Q18、Q19 暂缓（6.2.1）；`ai.launcher` 与 Q5 开关行的设计稿已定稿（Pencil XqqLV）；AI 与各部分之间统一走 2.9 的工具接口；另有几件事项保持开放，到相应阶段再定。本轮只做设计，不改产品代码。
> 基线：分支 `feat/ui-arch-revamp` @ `f4282769`；本文所在分支 `revamp/plugin-plan`。
> 调研方式：只读源码与文档，没有运行构建、应用或仓库脚本。文中 `文件:行号` 均指该基线；凡是没有读到代码证据的判断，都明确标为"推测"或"待核实"。
> 相关文档：[V0.2 插件宿主](../DESIGN/V0.2_PLUGIN_HOST.md)、[V0.5 网页连接](../DESIGN/V0.5_WEB_CONNECTION.md)、[UI 架构 Revamp](../ui-revamp/ARCHITECTURE_PLAN.md)、[Yix 例外登记](../ui-revamp/YIX_EXCEPTIONS.md)。

## 目录

0. 结论摘要
1. 现状盘点
2. 目标模型
3. 分层与 check-arch
4. 安全模型
5. 迁移路线
6. 风险、开放问题与备选方案
7. 附录：证据索引

---

## 0. 结论摘要

1. **现在的"插件"是编译期静态链接的会话协议适配器**，清单是一个 Zig 结构体，没有磁盘格式、没有运行期加载。注册表强制"一个插件 = 一个会话工厂 + 一种内容 renderer"，所以它表达不了"无会话的 tab content"，也没有任何面向用户的能力声明。设置页的说明和权限文案是按插件 ID 写死的，"计划中"是一份与注册表无关、已经过时的硬编码枚举。
2. **目标模型：插件 = 清单 + 若干贡献（Contribution）**。贡献的种类是协议（连接 + 会话）、内容卡片、设置分区、命令、AI 工具、通知。会话工厂从"必填"放宽为"声明了协议贡献才必填"。
3. **能力不由任何人手写，而是从清单里已被机器校验的声明推导出来**（服务、集成标志、工具、贡献）。宿主维护一份能力目录，每个条目带一个"证据谓词"；"N 项能力"和"能力对照表"是这份目录对注册表快照求值的结果。插件自有的能力可以显式声明，但必须指向自己真实注册的服务或工具，否则注册失败。
4. **"计划中"用独立的路线条目表示，不是清单的 `status` 字段**。路线条目只有名字、目标版本和设计文档路径，没有能力、没有版本号、不能创建会话；与已注册插件 ID 冲突时注册失败，从而保证条目不会过期。
5. **内容卡片（content card）是一等贡献**：tab 是一组卡片的容器，tab body 的分屏由多张卡片组成，独立 tab 只是单卡的特例。每个卡片类型声明三项放置约束：能否独立成 tab、能否进分屏、能否浮动；没有"停靠"这种放置（用户判定，6.2.1）。浮动卡片可以在整个窗口内容区里拖放，但仍归属打开它的 tab，切换 tab 时收回到该 tab、切回时展开（2.5.7；收回动效依赖 zenit 上游补齐 Z12）。分屏与分组复用现有的 workspace / group 实现，只把叶子从"会话"泛化为"卡片"。终端、文件、会话记录、AI 对话都是卡片类型，由各自的 feature 登记，不搬进 `src/plugins`。会话记录是一张内部含列表与详情的完整卡片；AI 对话只能浮动，现有的右侧停靠模式要删除（5.2 的 PL4b、PL4c）。
6. **插件 UI 与 feature 完全同构**：`model / view（.yix + .yss）/ host`，再加一个只给插件用的 `engine` 层；基础组件只用 zenit 原生。
7. **安全：只做编译期链接，本方案不引入任何运行期加载**。信任分三级（内置 / 随应用提供 / 经审计后 vendoring 的外部源码），权限用"宿主只注入已声明的 facade"加 check-arch 静态规则落实，并明确说明这不是沙箱。第三方可执行扩展的正路是进程外的 MCP（V0.4 已规划），不是进程内插件。
8. **新增一层 `src/plugin_api`** 作为插件能 import 的唯一宿主面；core 与 features 都不再 import `src/plugins/**`（门面也不行）。check-arch 增加 6 条规则（含机检 Q8 的 `ident:no-dylib`），其中字符串字面量、`extern` 等的匹配需要先给 check-arch 加一次小的工具扩展（3.3）；现有 100 条插件相关基线条目按阶段清零。
9. **路线分 PL0–PL6 七个阶段**，与 UI 重构的衔接点是：PL1（清单真实化）排在 PL2（协议插件面板按设计稿重建，不经 P3 的像素等价改写）之前；PL3（分层）并入 P5 的插件分层；PL4（内容卡片）跟随 P5 波次 C；PL5（插件视图 Yix 化）是 P5 的第二步；V0.5 网页连接作为新模型的第一个验收者。
10. **开放问题**见 6.2。Q1–Q12、Q14、Q15 已判定（6.2.1）。其中 Q5 的判定是"做"：随应用提供（`bundled`）的插件可以在设置里禁用，机制放在 PL1，界面开关放在 PL2，不再推到 PL6（设计见 6.2.1 的 Q5）。Q5a–Q5c、Q16、Q17 也已判定（第三批）；Q18（hardened runtime）、Q19（审计 checklist 写进 `AGENTS.md`）暂缓。浮动放置的第四批判定（整个窗口可停放、切换 tab 时收回到所属 tab）见 6.2.1 与 2.5.7，由此带出的 Q20（浮动卡片可以覆盖状态栏）、Q21（每个 tab 最多一张浮动会话记录卡片）也已判定。AI 能力只在卡片类型上配置、tab 能否启动 AI 由此派生、AI 统一绑定到 tab（第六批，2.5.8），由此带出的 Q22–Q24 已判定（第八批）：会话记录卡片不自动提供上下文；是否参与只看卡片类型、与放置无关；上下文改为模型调用内置工具 `host.tab_context` 拉取（新包 M11）。AI 入口不再是标题栏的 `toolbar.ai`，改为每个 tab 自己的浮动 AI 图标 `ai.launcher`（第七批，位置等待设计稿）。`ai.launcher` 与 Q5 开关行的设计稿已定稿（Pencil XqqLV）。仍开放、到相应阶段再定的：zenit 上游 Z12（收回动效）与 Z13（Card Type 禁用样式）的排期。

11. **GLM 交叉评审**的 15 个问题与 C、E、F 节的补充逐条处理，见 6.5；与插件化无关的发现（打包未启用 hardened runtime 等）登记在 6.4。
12. **AI 与 ZeroWork 各部分之间只通过统一的工具接口沟通**（2.9）：一个 `ToolDef`、一条调用流水线、一个注册表、一套 schema 约定，一方内部不用 MCP、不加协议层，需要对外时一对一导出为 MCP tool。AI 上下文是拉取的：`host.tab_context` 只给 tab 里各 AI 卡片的概览，细节由各卡片类型自己的固定 schema 工具负责（2.5.8）。

---

## 1. 现状盘点

### 1.1 "插件"现在是什么

| 问题 | 事实 | 证据 |
|---|---|---|
| 加载方式 | 同一可执行文件内静态链接。仓库里没有 `DynLib`、`dlopen`、磁盘清单解析 | 全仓 grep 无命中；V0.2 设计明确"没有动态市场、下载、热加载、热卸载或沙箱承诺"（`docs/DESIGN/V0.2_PLUGIN_HOST.md:30`） |
| 清单格式 | Zig 结构体 `PluginManifest`，含函数指针和编译期类型令牌，不可序列化 | `src/host/plugin_registry.zig:117-150` |
| 宿主 API 版本 | 只有主版本号，当前为 2；注册时不等于 2 即拒绝 | `plugin_registry.zig:3`、`:247` |
| 来源 | 只有 `builtin`、`bundled` 两种 | `plugin_registry.zig:67` |
| 组合根 | 两个：`linked_plugins.zig` 注册 local / ssh / sftp；`application_plugins.zig` 注册 bmc_ikvm 和测试夹具 | `src/plugins/linked_plugins.zig:65`、`:132`；`src/plugins/application_plugins.zig:10` |
| 测试夹具隔离 | `-Dplugin-fixture` 必须配合 `-Dtest-mode`，否则构建直接 panic | `build.zig:23-24`、`:212` |
| 宿主给插件的上下文 | `HostContext`：一组可空的受限 facade（配置解析、传输、凭据、秘密、信任、任务、通知、挑战、呈现、审计、偏好）。文件头注释写明"不是沙箱边界" | `src/host/host_context.zig:1-2`、`:39-55` |
| 插件 UI 接入 | 宿主把 `cx / scope / slot` 交给插件，由插件命令式建节点：`EditorMount`（连接编辑槽）、`ContentMount`（内容槽） | `src/host/plugin_ui_contract.zig:28`、`:78`、`:113` |
| 设置贡献 | `settings_section` 是字段 schema（布尔 / 字符串 / 选项），控件由宿主画 | `plugin_registry.zig:80-88`；存储在 `src/config/config.zig` 的 `plugin_preferences` |
| AI 工具 | `ToolDefinition`（含 `effect`、`approval_policy`）与 `ToolBinding` 分离，注册时校验 | `src/ai/plugin_tools.zig:9-48`；`plugin_registry.zig:233-251` |

### 1.2 注册表把"插件"等同于"会话协议"

`PluginHost.publish()` 的校验里有两条硬约束：

- 没有 `session_factory` 即 `MissingSessionFactory`（`plugin_registry.zig:249`）。
- `workspace_kind` 必须等于 `content_renderer`，并且能找到同名 renderer，否则 `MissingRenderer`（`plugin_registry.zig:275`）。

后果：清单表达不了"只提供一种 tab content""只提供命令""只提供 AI 工具"的插件。内容槽契约也只认会话——`ContentMount.owner` 的类型是 `SessionHandle`（`plugin_ui_contract.zig:78-87`），内容服务工厂的参数也是 `SessionHandle`（同文件 `:127-130`）。

### 1.3 内置三个协议没有自己的清单

local / ssh / sftp 的清单不是各自声明的，而是 `linked_plugins.registerAll` 遍历 `builtin_descriptors`，再对 `descriptor.plugin_id` 做 7 处 `switch` 拼出来的（`linked_plugins.zig:80`、`:86`、`:87`、`:95`、`:108`、`:114`、`:121`）。支撑这套拼装的是一组 legacy 桥：

- 闭枚举 `LegacyPluginId { local, ssh, sftp, external }`、`LegacyWorkspaceKind`、`LegacyServiceKind` 与 16 位服务位图（`plugin_registry.zig:6-35`）。
- 清单上的 `legacy_descriptor`、`legacy_registration` 字段（`plugin_registry.zig:144-145`），`session_host.zig` 仍有 6 处读它们（`:588`、`:824`、`:920`、`:971`、`:1122`、`:1169`）。

`src/plugins/remote/` 不是插件，而是 SSH 与 SFTP 共用的连接编辑器（`editor.zig` 4,403 行），被 `features/connections` 的 5 个文件直接 import。`src/plugins/ssh/` 没有 `plugin.zig`。

### 1.4 没有能力声明；设置页按插件 ID 写死文案

- 清单里与"能力"沾边的只有机器用的声明：`services` / `required_services`（类型化服务）、`integration`（6 个布尔标志，`plugin_registry.zig:72-79`）、`tools`、`notifications`。没有任何给用户看的能力字段。
- 设置页的"说明"和"权限"由两个按 ID 分支的函数给出：`description()`、`permissions()`（`src/features/settings/view/panes/settings_plugins.zig:80-91`）。非内置插件的说明回落成 `workspace_kind` 字符串，权限回落成一句通用文案。这正是 V0.2 §8.0.2 明令禁止的"公共模块按插件 ID 分支"。
- 同一文件的注释写着"只展示已注册的元数据，不为协议编造能力"（`settings_plugins.zig:16-17`）。所以设计稿 T5k96 的"N 项能力"、KUKQ5 的能力清单、ibeKI 的能力对照表目前都没做（`docs/ui-revamp/PENCIL_MAP.md:149` 也记录了这一点）。
- 仓库里同时存在四套互不相通的"能力"词表：legacy 服务位图；类型化 `ServiceKey`；`capability_snapshot.zig` 按 `ServiceKey` 做的动作投影；`actions.zig:62` 的 11 项 `Capability` 枚举（菜单与快捷键门禁用）。

### 1.5 "计划中"是一份过时的硬编码

`src/config/plugin_page.zig:6-20` 定义了 `PlannedProtocol { ftp_ftps, vnc, rdp, kvm }` 和 `plans` 表，版本写"未发布"、ABI 写"待定义"。问题有三个：

1. 它与注册表无关，是手写的。
2. 它已经过时：`kvm` 仍在计划表里，而 `bmc_ikvm` 早已作为真实插件注册（`src/plugins/bmc_ikvm/plugin.zig:105-129`）；设计稿里唯一的计划项"网页连接（0.5）"反而不在表里。
3. 同一文件还有 `PreviewKind { capabilities, permissions, validation, incompatible, wait_sessions, acquisition, loading }` 和一组"校验示例输入"（`:8`、`:27-30`）。这是为并不存在的安装 / 授权 / 加载流程准备的演示状态，只被预览 runner 和测试使用；当前插件列表只遍历真实清单，不渲染 `plans`（`settings_plugins.zig:18-66`）。

### 1.6 tab content 现在怎么建模

- 模型层：`ContentOwner = union(enum) { session, group, history }`，是闭合联合（`src/host/identity.zig:82-86`）。
- 视图层：`SessionTab` 没有"卡片类型"字段，靠一组可选字段和布尔标志区分——`terminal`、`file_ready`、`archived`、`local`、`plugin_renderer`、`plugin_protocol_id`（`src/features/workspace/view/workspace.zig:107-145`）。
- 插件内容：`ApplicationHost.safeTick` 每帧找出已就绪的会话，按 `manifest.content_renderer` 字符串查 renderer，再调 `Workspace.createPluginSession`（`workspace.zig:5252`）。内置的 terminal 和 file 不走这条路，它们是 `shared_renderer = true` 的占位（`linked_plugins.zig:19-22`），实际由 workspace 直接创建。
- **会话记录**：记录列表是一个全窗口浮层，绝对定位、`z_index = 500`、带焦点陷阱（`src/features/history/host/history_host.zig:66-70`），从标题栏按钮或资产右键菜单打开。点"回放"后才变成 tab：`openArchivedContent` 建一个 `content_owner = .history` 的 `SessionTab`，内容是一个处于归档模式的终端视图（`workspace.zig:5630` 起）。这是仓库里唯一的"无会话 tab"先例。
- **AI 对话**：是主窗口根节点下的一个面板，默认停靠在工作区右侧（`src/features/ai/pane/view/ai_pane_layout.zig:20`），`toggleDocked` 可切到同窗口内的浮动卡片（`src/features/ai/host/ai_host.zig:3784`）。停靠模式已判定删除（6.2.1、PL4c），这里记录的是基线上的现状。它不是 tab，`ContentOwner` 也没有对应变体。它的绑定对象是当前活动的会话或会话组。
- **分组与分屏**：组 tab 的 owner 是 `.group`，成员 tab 以 `container` 指向它；组内布局是 `group_layout.Tree` 二叉分屏树，叶子是会话身份；只有 `.session` owner 且未归档的 tab 能入组（`workspace.zig:2179-2185`）。这套实现与 2.5 的卡片模型的对应关系见 2.5.2。
- 没有通用的"卡片注册表 / 停靠 / 浮动"抽象。`retained_panel` 只负责把隐藏的面板从树上摘下来，目前只服务设置面板和 AI 面板。

### 1.7 耦合点清单

**(a) core 反向依赖插件**（check-arch 基线里 `layer:core->legacy_plugin` 7 条、`layer:core->plugin_registry` 1 条）

| 来源 | 目标 | 性质 |
|---|---|---|
| `src/host/session_host.zig:363` | `plugins/linked_plugins.zig` | 运行期路径：会话宿主自己去拉组合根 |
| `src/local/adapter.zig:391` | `plugins/local/config.zig` | 运行期路径 |
| `src/ai/{image_offload,plugin_tools,tool_results}.zig` | `plugins/bmc_ikvm/{tools,framebuffer,observation_image}.zig` | **已核实：6 处全部在文件内测试块里**（`image_offload.zig:389`、`:434`、`:440`，`plugin_tools.zig:892`，`tool_results.zig:482`、`:489`；三个文件的第一个 `test` 分别在 `:214`、`:859`、`:480`）。check-arch 对测试块里的 import 同样计入层矩阵，所以基线仍有这 6 条；清零手段是把这几个测试挪到 bmc 自己的 `tests/` |
| `src/host/plugin_ui_contract.zig:4` | zenit `ui` | core 里的 UI 契约，另记为 `layer:core->zenit_ui` |

**(b) features 直接 import 插件内部文件**（基线 `layer:host->legacy_plugin` 21 条、`layer:view->legacy_plugin` 6 条、`cross-feature` 31 条中的大部分）

- `features/connections/**` → `plugins/remote/{editor,editor_factory,challenge_bridge}.zig`
- `features/ai/tools/host/{ai_tools,ai_host_queries}.zig` → `plugins/bmc_ikvm/` 的 6 个内部文件；`ai_lifecycle_controller.zig` → `plugins/ssh/terminal_service.zig`。其中非测试代码的是 `ai_host_queries.zig:10-11`（`console_service`、`tools`）；`ai_tools.zig:1280` 与 `ai_lifecycle_controller.zig:1502`、`:1540`（`@ptrCast` 成 ssh 的 `Provider`）在测试块里（核实于 GLM 评审之后）
- `features/workspace/view/workspace.zig:1321` → `plugins/bmc_ikvm/model.zig`；多处 → `plugins/ssh/{connect_job,runtime_binding}.zig`
- `features/files/host/file_application_host.zig:3` → `plugins/sftp/provider_host.zig`
- `features/shell/host/application_host.zig:94`、`:245-247` → `plugins/ssh/connection_source.zig`、`plugins/linked_plugins.zig`

**(c) 公共代码按插件 ID 分支**（V0.2 §8.0.2 禁止，但仍然存在）

| 位置 | 分支内容 |
|---|---|
| `features/settings/view/panes/settings_plugins.zig:80-91` | 说明与权限文案 |
| `shared/ui/components/session_icon/session_icon.zig:84`、`:98` | `"bmc_ikvm"` 图标、`"ssh"` / `"sftp"` 的系统图标回退 |
| `features/shell/host/nav_host.zig:247` | `selectContribution("bmc_ikvm")` |
| `features/workspace/view/workspace.zig:1321-1322` | 侧栏路由对 bmc 的特判 |
| `features/ai/tools/host/ai_host_queries.zig:161`、`features/ai/approvals/view/ai_tool_approval_view.zig:181` | `"bmc_ikvm"` |
| `src/host/{file_route_factory,sftp_adapter,socks_route_host}.zig`、`features/connections/progress/host/ssh_status_host.zig:60` | `pluginId() != .ssh / .sftp` |
| `src/host/transport_factory.zig:84`、`src/config/connection_envelope.zig:61`、`:164` | `"ssh"` / `"sftp"`（其中 envelope 的 legacy 解码属于 V0.2 允许的兼容 codec 边界） |

**(d) 插件反向依赖 feature 内部**：`plugins/remote/editor.zig` → `features/workspace/host/session_runtime.zig`；bmc 的预览 runner 与测试 → `features/{shell,connections,terminal,workspace}` 的内部文件（基线 `cross-feature` 条目）。

**(e) check-arch 现状**：插件走过渡布局——`src/plugins/*.zig` 归 `plugin_registry` 层，`plugins/<p>/{non_ui,plugin}.zig` 归门面，其余归 `legacy_plugin`（`tools/arch/rules.zon:78-82`）。基线 1,033 条里有 100 条涉及 `plugins/`（口径：`grep -c 'plugins/' tools/arch/baseline.txt`，即来源或目标路径里出现 `plugins/` 的行；PL3、PL5 的"清零"按同一口径验收）。按规则分布：`cross-feature` 31、`layer:host->legacy_plugin` 21、`layer:legacy_plugin->view` 12、`layer:core->legacy_plugin` 7、`layer:view->legacy_plugin` 6、`ident:no-inline-style` 5、`ident:no-widget-internals` 4、`layer:legacy_plugin->host` 4、`layer:plugin_registry->host` 3、`layer:tests->plugin_registry` 2，其余 5 类各 1。Revamp 方案把这些过渡条目留到 P5 处理。

### 1.8 设计稿与代码的差距

| 设计稿（T5k96 / KUKQ5） | 代码事实 | 本方案的处理 |
|---|---|---|
| 每个协议显示"N 项能力"（本地 5、SSH 8、SFTP 3、BMC 2），对照表共 10 项 | 清单不声明能力 | 由能力目录推导，数字以推导结果为准，不照抄设计稿 |
| KUKQ5 把"文件浏览与传输"列为 SSH 不支持、"由 SFTP 提供" | SSH 清单声明了 `directory`、`file_read`、`transfer` 服务，并带 `auxiliary_readonly`、`auxiliary_transfer` 标志（`linked_plugins.zig:95-100`、`:121-126`） | 设计稿这一条与代码不符，以代码为准（Q10） |
| "随应用提供"分组里有 Ansible（ansible-core 2.17.4） | 源码、设计文档、e2e 中均无 Ansible | 不显示（Q6） |
| "计划中"分组：网页连接，"0.5 版本待实施"，无能力数、无箭头 | 计划表里是 FTP / VNC / RDP / KVM | 路线条目，见 2.6 |
| 列表 → 单协议详情页（两级导航） | 主从布局：左侧 216pt 列表 + 右侧详情 | PL2 |
| "输入广播""应用指令（@）""会话录制"作为协议能力 | 清单层没有对应声明；广播的门禁条件是"终端 + 会话组"（`actions.zig` 的规则） | 只有找到与门禁同源的证据才进目录，见 2.3 |

---

## 2. 目标模型

### 2.1 概念

| 概念 | 定义 |
|---|---|
| 插件（Plugin） | 一个有稳定 ID 的扩展单元：一份清单 + 它登记的贡献。源码在 `src/plugins/<id>/` |
| 贡献（Contribution） | 插件向宿主某个扩展点登记的一项东西。种类固定：协议、内容卡片、设置分区、命令、AI 工具、通知 |
| 能力（Capability） | 给用户看的"这个插件能做什么"。由宿主从清单的机器声明推导，或由插件声明并附证据 |
| 权限（Permission） | 插件需要宿主注入哪些敏感 facade。固定词表 |
| 路线条目（RoadmapEntry） | "计划中"的协议。不是插件，没有清单 |
| 内容卡片类型（content card type） | 一种界面内容。它的实例（卡片）可以按类型声明的约束放进 tab（独立或分屏）或浮动层 |

feature 也可以登记贡献（主要是卡片类型），但 feature 不是插件，不出现在"协议插件"设置页。理由见 2.5 与 6.3-A2。

### 2.2 清单

在现有 `PluginManifest` 上做**加法**，现有清单不改也仍然合法。宿主 API 记为 2.1（新增 `minor` 字段；主版本仍为 2）。选择次版本而不是 API 3 的理由：V0.4、V0.5 的设计都明确"不以 API 3 为前置"（`docs/DESIGN/README.md:26`），而这里的每一项改动都是放宽或新增可选字段。

```zig
pub const PluginManifest = struct {
    // —— 身份（现有，除 summary / host_api_minor）——
    id: []const u8,
    display_name: []const u8,
    summary: []const u8 = "",            // 新增：一句话说明，取代设置页按 ID 写死的 description()
    plugin_version: []const u8,
    origin: Origin,                      // builtin | bundled；本方案不新增第三种
    host_api_version: u32 = 2,
    host_api_minor: u32 = 0,             // 新增；使用新字段的清单写 1
    order, dependencies, provides, icons, // 现有

    // —— 贡献 ——
    connection, quick_create,            // 现有：协议贡献
    session_factory: ?SessionFactory,    // 现有；改为"有协议贡献才必填"
    cards: []const CardRef = &.{},    // 新增：登记或引用卡片类型（2.5）
    settings_section,                    // 现有
    commands: []const CommandContribution = &.{}, // 新增（PL6，2.7）
    tools, tool_definitions, ai_context, notifications, // 现有
    services, required_services, integration,           // 现有

    // —— 声明 ——
    permissions: []const Permission = &.{},        // 新增（4.3）
    capabilities: []const CapabilityClaim = &.{},  // 新增：仅插件自有能力（2.3）
};
```

过渡期保留 `workspace_kind` / `content_renderer`，等价于 `cards` 里的一条会话绑定内容，PL4 结束时删除。`legacy_descriptor` / `legacy_registration` 在 PL3 删除。

注册校验（`publish`）在现有两阶段流程上增加：

1. 有 `connection` 或 `quick_create` 时才要求 `session_factory`；两者都没有时，`cards`、`commands`、`tools`、`settings_section` 至少一项非空，否则拒绝（空插件）。
2. `capabilities` 的每一项必须有证据且证据成立（2.3）。
3. `dependencies` 里出现的敏感宿主 API 必须被 `permissions` 覆盖（4.3）。
4. 清单只要有 `tools`、`integration.ai = true` 或 `ai_context != null` 中的任何一项，或者它定义的卡片类型声明了 AI 能力（`CardTypeDef.ai != null`，2.5.8），就必须声明 `ai_integration` 权限，否则拒绝（4.3；GLM B-2）。PL4a 之后 AI 能力只在卡片类型上声明，前三项清单字段随之删除，这一条只剩"定义了带 AI 能力的卡片类型或登记了工具"。由 features 登记的卡片类型（终端、文件等）不属于任何插件，不受这条约束。
5. `cards` 引用的卡片类型必须存在；登记的种类 ID 全局唯一。
6. 路线条目与已注册插件 ID 冲突即拒绝（2.6）。这条校验要放在一个同时包含全部生产清单和 `roadmap.zig` 的测试里；只带 fixture 的测试根（`tests_plugin_fixture.zig`）不足以发现冲突。
7. `settings_section` 的字段键不得以 `host.` 开头。这个前缀留给宿主自己存放的每插件设置，例如 Q5 的启用状态（6.2.1）。

### 2.3 能力：推导，不手写

**原则**：能力是事实的另一种读法，不是另一份数据。清单里已经有被注册表校验、被运行期门禁消费的声明；能力展示必须与它们同源。

**能力目录**（宿主维护，位于 core，纯数据）：

```zig
pub const CapabilityDef = struct {
    id: []const u8,          // "terminal"、"forward"、"reconnect" …
    label: []const u8,       // "交互终端"
    evidence: Evidence,
};
pub const Evidence = union(enum) {
    service: ServiceKey,                 // 清单声明了该服务
    all_services: []const ServiceKey,
    integration: IntegrationFlag,        // 清单的 integration 某标志为真
    any_of: []const Evidence,            // 任一成立即成立；用于门禁本身是"或"的情况
    ai_context,                          // ai_context != null
    has_tools,                           // tools.len > 0
    content: []const u8,                 // 登记或引用了某卡片类型
    probe,                               // connection.probe_factory != null
    temporary_connection,                // create_kind == saved_or_temporary
};
```

一个插件"具有"某项目录能力，当且仅当该条目的证据谓词对它的清单为真。于是：

- **"N 项能力"** = 目录中对该插件成立的条目数 + 该插件自有能力数。
- **单协议页的"支持的能力"** = 成立的条目；**"不支持"** = 不成立的目录条目，"由 X 提供"是对其余清单求值的结果。
- **能力对照表** = 目录条目 × 已注册协议插件的布尔矩阵。

这三处都是注册表快照的纯函数，没有任何人为某个插件写"支持 X"。

**插件自有能力**（目录里没有、只属于某个插件的，例如 BMC 的"电源控制"）：

```zig
pub const CapabilityClaim = struct {
    id: []const u8,          // 必须以插件 ID 为前缀："bmc_ikvm.power"
    label: []const u8,
    evidence: union(enum) { service: ServiceKey, tool: []const u8, content: []const u8 },
};
```

证据必须指向同一份清单里真实登记的服务、工具绑定或卡片类型，否则 `publish` 返回 `CapabilityWithoutEvidence`。插件不能用自有声明冒充目录能力：ID 没有本插件前缀即拒绝。

**目录条目的准入规则**（防止目录本身变成新的"编造"来源）：

1. 每个条目的证据必须是清单上的机器声明，不能是插件 ID。
2. 该能力对应的功能如果有运行期门禁，门禁必须读同一个声明。例如"断线重连"的证据是 `integration.transport_loss`，而 `session_host.zig:1077` 的重连判定读的正是这个标志。
3. 找不到这样的声明的功能，不进目录。设计稿里的"输入广播""应用指令（@）""会话录制"目前就属于这一类：要么先在清单层补上真实声明并让门禁改读它，要么不列。PL1 逐项审计后定稿。（已核实：`actions.zig:70-71` 的 `groups`、`recording` 两个能力位在 `serviceCapability`（`:266-270`）里被当作服务能力，但清单的服务表里没有对应的服务名，有能力快照时直接跳过，没有快照时回落到调用方手填的 `context.supported`（`:295-298`）。`recording` 实际来自 ssh `terminal_service` 的录制查询，`groups` 来自 workspace 的 roster。两者都没有清单层来源，所以"输入广播""会话录制"按本规则暂不进目录。）

基于现有声明、可以直接成立的初始候选（最终清单由 PL1 的审计给出）：

| 能力 | 证据 | 现有门禁读同一声明的位置 |
|---|---|---|
| 交互终端 | 服务 `terminal` | `actions.zig` 的规则；`ai_host_queries.zig:104` |
| 命令执行 | 服务 `exec` | `ai_host_queries.zig:105` |
| 跳板路由 | 服务 `route` | `actions.zig:152` |
| 端口转发（SOCKS） | 服务 `forward` | `actions.zig:161` |
| 文件浏览 | 服务 `directory` + `file_read` | `session_host.zig:1149` |
| 文件传输 | 服务 `transfer` | `actions.zig:156`；`session_host.zig:1157` |
| 断线重连 | `integration.transport_loss` | `session_host.zig:1077` |
| 附着 AI 助手 | PL1–PL4a 之间：`any_of { integration.ai, ai_context }`；PL4a 起：插件定义或引用的卡片类型中至少一个声明了 AI 能力（`card_ai`，2.5.8） | 用户已判定 AI 能力只在卡片类型上配置（6.2.1 第六批）。PL1 先把 `ai_host.zig:653`（`integration.ai or ai_context != null`）与 `ai_session_context.zig:8`（只读 `integration.ai`）两处门禁收敛到同一个谓词函数，取前者的"或"（今天所有清单的 `integration.ai` 都为真，收敛不改变任何行为）；PL4a 再把这个函数改为从卡片类型派生。原先"两处读法不一致"的开放问题就此消解 |
| AI 工具 | `has_tools` | 工具目录注册校验；目录枚举时还要求 `integration.ai`（`ai_tools.zig:328`） |
| 连接测试 | `probe` | 编辑器的测试入口；`plugin_registry.zig:97` 的 `probe_factory` |

GLM 评审核实后补充的候选（是否进目录由 PL1 的审计决定，审计标准同上）：

| 候选 | 证据 | 门禁 | 备注 |
|---|---|---|---|
| 本机进程 | 服务 `process` | 待 PL1 核对 | local、ssh 都声明了（`linked_plugins.zig:95-96`） |
| 认证与凭据 | 服务 `auth` | 待 PL1 核对 | ssh、sftp 声明了 |
| 辅助只读文件 | `integration.auxiliary_readonly` | `session_host.zig:1293` | 与"文件浏览"可能重复，PL1 决定合并还是分列 |
| 辅助传输 | `integration.auxiliary_transfer` | `session_host.zig:1490`（与 `directory_recovery` 是"或"） | 同上 |
| 目录恢复 | `integration.directory_recovery` | `session_host.zig:1490` | sftp 声明了 |

`integration` 的 6 个标志在源码里的注释是"描述 legacy 独立文件引擎，从不用来识别插件"（`plugin_registry.zig:71`）。把它们当作能力证据合乎准入规则 2，但标签要按用户能理解的功能来写，不能直接照搬标志名。

**声明不等于此刻可用**。V0.2 §6 已经区分 declared / available / authorized 三态；设置页展示的是 declared，会话级的可用与授权仍由 `CapabilitySnapshot` 负责。设置页的文案要写"支持的能力"，不写"已启用"。

**四套词表的收敛**：不在本方案早期阶段强行合并。约束是从 PL1 起不再新增第五套，且 `actions.zig` 的 `Capability` 在 PL6 改为引用目录 ID（列为后续项，不阻塞前面的阶段）。

### 2.4 生命周期

| 环节 | 编译期链接下的含义 |
|---|---|
| 发现 | `src/plugins/index.zig` 里的一张编译期表，是全仓唯一允许按 ID 列举插件的地方，取代现在的两个组合根。测试夹具仍由 `-Dplugin-fixture` 选入 |
| 校验 | `publish()` 的两阶段校验：全部通过才一次性发布不可变快照，任何一项失败都不留下半张注册表（现有行为，保留） |
| 运行状态 | 宿主计算，不写在清单里：`available` / `unavailable(原因)` / `disabled`。`unavailable` 用于"已注册但当前平台或依赖不满足"（V0.5 §2 要求的"给出标准不可用原因"） |
| 启用 / 禁用 | **Q5 已判定要做**，设计见 6.2.1 的 Q5。要点：只对 `bundled` 生效（内置三项不能禁用，Q5a 已判定）；被禁用的插件在启动时不初始化、不进注册表，因此它的创建入口、服务、AI 工具、通知定义都随快照消失；已保存的主机按 V0.2 §4.2 的"未知插件可列出、不可连接"路径处理，并显示"已禁用"这个具体原因；状态存放在 `[[plugin_preferences]]` 的保留键 `host.enabled`；切换在下次启动时生效。机制在 PL1，界面开关在 PL2 |
| 更新 | 插件随应用更新。应用更新已有 Ed25519 签名清单（`src/update/crypto.zig`）和 AGENTS.md 的 commit 一致性流程，插件不另设通道 |
| 版本 | `plugin_version` 用于展示与诊断；payload 版本、服务主版本、宿主 API 版本各自独立管理（现有约定，保留） |

### 2.5 内容卡片（content card）

> 2026-11-13 按用户意见修订。用户原话："我觉得 tab 和 tab body 里 split view 里是一个东西，只是这种 content card type 可以配置约束，哪些可以单独开 tab，哪些不可以。"与修订前的差别见本节末尾。

#### 2.5.1 模型

- **内容卡片（content card）是唯一的内容抽象**。终端、文件、KVM 画面、会话记录、AI 对话，以及以后插件提供的内容，都是某种**卡片类型（content card type）**的实例。
- **tab 是一组卡片的容器**。tab body 是一棵分屏树，叶子是卡片。"单独开一个 tab"只是"分屏树只有一个叶子"的特例。所以 tab 与分屏窗格不是两种内容，而是同一张卡片的两种放置。
- **每个卡片类型声明自己的放置约束**；宿主在每一次放置和移动时校验约束，不靠"界面上不提供入口"来保证。

三种放置（"停靠"已由用户判定删除，见 6.2.1；分屏只指 tab 内分屏，没有窗口级的停靠槽位）：

| 放置 | 含义 | 承载者 |
|---|---|---|
| `standalone_tab` | 作为某个 tab 里唯一的一张卡片 | tab 容器（单叶分屏树） |
| `split` | 进入某个 tab 的分屏树，与其他卡片并排 | tab 容器（多叶分屏树） |
| `float` | 同一窗口内的浮动卡片，位于 tab body 之上；**拖拽与停放范围是整个窗口的内容区，不受 tab content 边界限制**，但仍归属打开它的 tab，切走时收回到该 tab（2.5.7，用户判定见 6.2.1 第四批） | 窗口级浮动层 |

#### 2.5.2 这个模型在现有代码里已经有一半

现有的"会话组"就是"一个 tab 装多张卡片"，只是叶子被限定为会话：

| 新模型 | 现有实现 | 证据 |
|---|---|---|
| tab 容器 | 模型层的 `Tab`；组 tab 的 owner 是 `.group` | `src/features/workspace/model/workspace_model.zig:7-16`；`src/host/identity.zig:82-86` |
| 卡片属于哪个容器 | 成员 tab 的 `container: ?TabId`（注释："在组内创建的会话保留自己的 owner，但只有一个可见入口"） | `workspace_model.zig:15-16`；`workspace.zig:932`、`:1563-1564` |
| 分屏树 | `group_layout.Tree`：二叉分割，`Node = union { empty, leaf: u64, split }`，文件头写明"叶子持有会话身份，不持有协议对象" | `src/features/workspace/model/group_layout.zig:1-8` |
| 分屏布局持久化 | `group_layout.Snapshot`（`version = 2`），叶子是"有序成员槽位，恢复时重新绑定到活动 ID" | `group_layout.zig:2-3`、`:8`、`:139` |
| 卡片能否进分屏 | `canGroupTarget`：`!archived and !closing and !owned_pending and content_owner == .session`；窗格头的"分屏"按钮用同一条件 | `workspace.zig:2179-2185`、`:3367` |
| 分屏里每张卡片的头部 | `mountPaneHeader` | `workspace.zig:3261` |
| 组的语义（名称、颜色、成员、广播、组助手） | `group_model` 的 roster；AI 的 `tool_scope.Owner = union { session, group }` | `src/features/workspace/model/group_model.zig`；`src/ai/tool_scope.zig:6-8` |

所以不需要另起一套：把分屏树的叶子从"会话"泛化为"卡片"，把 `canGroupTarget` 里写死的条件换成"读卡片类型的约束"，现有的组 tab、分屏、拖拽入组、比例保存全部原样复用。

**布局与语义要分开**。今天"会话组"同时承担两件事：分屏布局的容器，以及广播 / 组助手的作用范围。泛化之后：

- **布局**：tab 的分屏树，叶子可以是任何允许 `split` 的卡片。
- **会话组（roster）**：同一个 tab 里**会话绑定**的卡片集合，继续是广播的作用范围，也是"N 个会话"的计数。非会话卡片即使在同一个分屏里，也不是组成员，不接收广播。
- **AI 作用域**（第六批判定之后，2.5.8）：同一个 tab 里**声明了 AI 能力**的卡片集合，与 roster 分开计算。今天声明 AI 能力的都是会话卡片，所以两者恰好重合；以后某种非会话卡片声明了 AI 能力，它进入 AI 作用域，但仍不是 roster 成员、不接收广播。

这样现有的组语义不变，新卡片类型也不会意外获得广播或执行权。

（`pane_manager.zig` 里另有一套 `Tab { panes }` / `Pane { session_id, group_id }` 模型。**已核实（GLM F-9，经复核修正）：它不在运行期路径上，只被测试引用。**引用它的是 `features/shell/model/shortcut_dispatch.zig:3` 与 `features/workspace/model/group_dispatch.zig:8`；这两个文件以及 `pane_manager` 本身，只在 `src/root.zig:94`、`:99`、`:101` 被导出，并在 `:282`、`:286`、`:288` 以 `_ = …` 的形式拉进测试；仓库里没有任何代码经 `zerowork` 模块使用这三个导出。GLM 说"`group_dispatch.zig` 没有这条 import"不对，它看的是 shell 目录，文件实际在 workspace/model 下。结论：卡片模型只以 `group_layout` / `group_model` 为准，不考虑 `pane_manager`。Q16 已判定：这三个只服务测试的文件连同其测试，在 PL4a 之前删除，单独一个包（5.2 的 PL4a）。）

#### 2.5.3 卡片类型的声明

类型分成两半，因为 core 不能 import zenit `ui`：

```zig
// core 一半：纯数据，进清单 / 注册表
pub const CardTypeDef = struct {
    type_id: []const u8,                    // "terminal"、"file"、"bmc_ikvm"、"history"、"ai.chat"
    title: []const u8,
    icon: []const u8,
    binding: enum { session, standalone, tab },  // session：需要 SessionHandle；tab：绑定所属 tab（只有 ai.chat）
    ai: ?CardAi = null,                     // AI 能力只在这里声明（2.5.8）；tab 上没有任何 AI 配置
    placement: packed struct {
        standalone_tab: bool,
        split: bool,
        float: bool,
    },
    default_placement: Placement,
    cardinality: enum { per_owner, single_per_window, multiple },
    float_per_tab: ?u8 = null,              // 每个所属 tab 最多几张浮动实例；history 为 1（Q15，按 tab 归属理解，2.5.7）
    supports_window_transfer: bool = false,
};
pub const CardRef = union(enum) { define: CardTypeDef, use: []const u8 };

// UI 一半：在 plugin_api/ui，由组合根登记到卡片宿主
pub const CardViewDef = struct {
    type_id: []const u8,
    create: *const fn (ctx: ?*anyopaque, CardOpen) anyerror!CardInstance,
};
pub const CardInstance = struct {
    context: *anyopaque,
    vtable: *const struct {
        mount: *const fn (*anyopaque, CardMount) anyerror!void,   // 只能在未挂载状态下调用，见下
        unmount: *const fn (*anyopaque) void,
        update: *const fn (*anyopaque, CardUpdate) anyerror!void, // 取代 RendererInstance.update
        focus_changed: *const fn (*anyopaque, bool) void,
        placement_changed: ?*const fn (*anyopaque, Placement) void = null,
        can_close: ?*const fn (*anyopaque) CloseRisk = null,
        connection_status: ?*const fn (*anyopaque) ConnectionStatus = null, // 沿用现有
        show_connection_details: ?*const fn (*anyopaque) void = null,      // 沿用现有
        destroy: *const fn (*anyopaque) void,
    },
};
/// 与现有 ContentUpdate（plugin_ui_contract.zig:88-93）同构；非会话卡片的 owner 是 CardId。
pub const CardUpdate = struct { owner: CardOwner, revision: u64, title: []const u8, status: []const u8 };
/// 带代次的卡片身份。代次是值的一部分，所以 ContentOwner.eql 沿用 std.meta.eql 也不会把复用槽位的新实例误判为同一张卡片。
pub const CardId = struct { slot: u32, generation: u32 };
```

注册校验：`placement` 三项不能全为假；`default_placement` 必须是允许的放置之一；`binding = .session` 的类型必须由带会话工厂的清单定义或引用。

**vtable 的约束（GLM B-4）**：

- 它必须覆盖要取代的 `RendererInstance`（`plugin_ui_contract.zig:94-108`）的全部能力：`update`（带 owner 与 revision）、`connection_status`、`show_connection_details` 原样保留，否则状态栏的连接入口与窗口移交时的内容刷新会丢失。
- `mount` 与 `unmount` 严格配对：宿主保证对同一实例在调用 `mount` 之前已经 `unmount`；对已挂载的实例再次 `mount` 是程序错误，适配层用断言拦住。`destroy` 之前宿主保证已 `unmount`。
- 今天窗口移交按"`plugin_renderer != null` 且 owner 相等"判断（`workspace.zig:5157`、`:5192`），改为按 `card_type` 加 owner 判断，PL4a 的等价性单测覆盖它。

**登记时序**（GLM C.c）：卡片类型的登记只发生在组合根里，在创建第一个窗口之前完成。app 先收集 features 门面导出的 `cardTypes()`，再收集插件清单的 `cards`，用与 `publish` 相同的两阶段校验一次性发布不可变快照；此后不接受运行期登记。features 的 host 与插件都不自己调用 `register`。

要点：

1. **实例与视图分离**。实例持有 view-model，从 `create` 活到 `destroy`；视图可以被 `mount` / `unmount` 多次。卡片在放置之间移动（从分屏拖出成独立 tab、从浮动变成 tab）= 宿主卸载视图、换一个槽位重新挂载，状态留在 view-model 里。这是 Revamp 方案 4.4 的契约，也沿用了 V0.2 §6 "窗口移交只移 view，不复制网络"。
2. **放置是宿主的事**，卡片不知道自己在哪。tab 与分屏由现有的 workspace / group 实现承载；浮动是窗口级的一个浮动层，由卡片宿主（归 `features/workspace/host`）承载。
3. **会话绑定的卡片**沿用现有语义：`owner` 是 `SessionHandle`，仍要过 `allowsContent`，仍带代次。现有的 `RendererDefinition` 是 `CardViewDef` 的特例，PL4a 用适配层包起来。
4. **卡片身份**：会话卡片继续用会话身份（与分屏树叶子现有的 `u64` 表示一致，已保存的布局快照不需要迁移）；非会话卡片由卡片宿主分配带代次的 `CardId { slot, generation }`，`ContentOwner` 增加变体 `card: CardId`。`ContentOwner.eql` 今天是 `std.meta.eql`（`identity.zig:87-88`），因为代次在值里，逐字段比较就能区分复用槽位的新旧实例；PL4a 为此加一条单测（同一 `slot`、不同 `generation` 判为不等）。`SessionTab` 增加显式的 `card_type` 字段，逐步取代 1.6 里那组布尔标志。
5. **谁能打开卡片**：宿主 UI（命令、菜单、拖拽）；feature 经 workspace 门面；插件经 `ports.cards.open`，且只能打开自己登记的类型。

#### 2.5.4 各卡片类型的约束

"依据"一列写明约束来自现有代码行为还是用户判定。

| 卡片 | type_id | 登记者 | binding | 独立 tab | 分屏 | 浮动 | 依据 |
|---|---|---|---|---|---|---|---|
| 终端 | `terminal` | `features/terminal` | session | 是 | 是 | **是**（cards-float） | 会话 tab 可入组（`canGroupTarget`）；用户判定“ssh类的也是可以floating的”（2026-11-14），见下 |
| 文件 | `file` | `features/files` | session | 是 | 是 | **是**（cards-float） | 同上；SFTP 可混合入组（`docs/DESIGN/README.md` 的 V0.3 混合会话组说明） |
| KVM 画面 | `bmc_ikvm` | bmc 插件 | session | 是 | 是 | **是**（cards-float） | 同上；它也是 `.session` owner，满足 `canGroupTarget` |
| 会话记录 | `history` | `features/history` | standalone | **是** | 否（已判定，模型保留开关） | **是**（默认） | 用户判定：一张完整卡片，内部是列表 + 详情。浮动是现状（今天是窗口内浮层） |
| AI 对话 | `ai.chat` | `features/ai` | tab（绑定所属 tab，2.5.8） | **否** | **是**（cards-float） | **是**（默认） | 用户判定，见下 |
| 网页（V0.5） | `web` | web 插件 | session | 是 | 是 | 否 | 与其他会话卡片一致；V0.5 §2 的"标准内容页" |

**AI 对话：浮动，也可以放进所属 tab 的分屏；不能单独成 tab。**

- **2026-11-14 改判（cards-float）**：用户原话“AI chat也是可以放回cards layout的”，覆盖下面“只保留浮动”中关于分屏的部分：`split = true`、`float = true`、`standalone_tab = false`（Q4 不变）。放进分屏后 AI 仍绑定在 tab 上（M10）：单卡 tab 放入 AI 变成组 tab 时，对话按 2.5.8 的交接规则交给组 tab；AI 浮动回去、组里只剩原来那个会话时组还原成单卡 tab，对话交还原 tab。launcher 图标保留（状态照常显示），停靠时点击聚焦停靠的 AI（输入框）。
- （原判定，分屏部分已被上一条取代）`standalone_tab = false`、`split = false`、`float = true`：用户判定（6.2.1 的 Q4 与"只保留浮动"两条）。
- 这与今天的行为不同。今天 AI 面板默认是工作区右侧的分栏（`ai_host.zig:64-66` 的注释；`ai_pane_layout.zig:20` 的 `docked: bool = true`），浮动是通过 `toggleDocked` 切过去的第二种形态（`ai_host.zig:3784`）。删除停靠模式是一项用户可见的行为变更，单列为迁移步骤，见 5.2 的 PL4c。
- 浮动形态本身是现成的：`src/ai/float_model.zig` 的几何模型（最小 520×354，`:6-7`；默认位置今天以 AI 条为锚点，见 `:178` 的测试；AI 条删除后的锚点见 PL4c）与 `ai_float_gestures.zig` 的移动和 8 向缩放，`e2e/ai_float_geometry_native.ts` 已覆盖。
- `split = false` 除了用户判定，也符合绑定语义：AI 绑定的是 tab 这个容器（2.5.8；今天的实现是"当前活动的组视图，否则当前活动 tab 的会话"，`ai_host.zig:549-562`），放进某个 tab 的分屏就成了自己所绑定容器的成员。

**会话记录：一张卡片，内部是列表 + 详情。**

用户原话："会话记录不用再分为列表和回放，它就像 FTP 一样，它就是一个独立的 card 完整的，有 list 和 detail。"（这里的"像 FTP"指文件工作区那种一张卡片里同时有列表和详情的形态，不是要实现 FTP 协议。）

- 只有一种卡片类型 `history`。卡片内部一侧是记录列表，选中一条后在同一张卡片里显示详情与回放。今天的三种形态——全窗口的记录浮层、点"查看"后新开的归档 / 回放 tab、回放条——都变成这张卡片的内部状态。
- 过渡期的身份（回应 GLM B-5；它评审的旧版本把列表与回放拆成两种内容，这个拆分已被用户判定取代）：H1–H4 期间，现有的归档 tab 仍是 `content_owner = .history`，身份是每次打开时运行期分配的 `HistoryId`（`workspace.zig:5653` 的 `history_ids.allocate()`；GLM 说它是"持久实体 ID"，复核不成立），同一条记录已打开时按 `archive_key` 由 `focusArchive` 复用（`:5576`），这些行为不变，它也不算 `history` 卡片；H5 删除这条旧路径后，`history` 卡片才是唯一形态，身份是 `card: CardId`。今天 `focusArchive` 那种"同一条记录不重复打开"的去重不再依赖 owner 判等；H4 是否保留这种去重（例如"作为 tab 打开"时发现已有 tab 选中同一记录就聚焦它），由执行者在 H4 的报告里写明，默认不去重，与 Q15 的"tab 可以开多张"一致。
- 这与设计稿 CC3v4 的方向一致，并且消掉了一条已登记的实现差异。`docs/ui-revamp/PENCIL_MAP.md:90` 记录：会话记录目录是"宽 300 的窗格"，回放条在"回放窗格底部"；同时登记了保留差异"目录仍是可 Esc 关闭的模态窗格（打开记录时关闭，不能和回放同时常驻）"。合并成一张卡片后，目录与回放同时常驻，这条差异不再存在。那句"停靠在 view island 左侧"按"只保留浮动"的判定应理解为卡片内部的列表栏，不是窗口级的停靠。
- 放置：独立 tab 是；浮动是（默认，沿用今天从标题栏打开即浮在窗口上的形态）；分屏初始为否——今天没有任何非会话内容进过分屏，先不放开（Q11 已判定：初始不允许，模型里保留 `split` 这个开关）。同时可以开多张 tab，浮动最多一张（Q15 已判定；按 tab 归属理解为"每个 tab 最多一张"，见 2.5.7）。
- 实时会话终端里的"打开只读历史页"（动作 `record.open_history`，`src/host/actions.zig:160`；`terminal.history.selected`，`workspace.zig:1803-1805`）是终端卡片自己的一个内部状态，不是归档 tab，也不是记录浮层，不在这次合并的范围内，保持不变（Q14 已判定：不并入）。

#### 2.5.5 现有 group / split / pane 怎么映射、要改什么

| 步骤 | 改动 | 行为 |
|---|---|---|
| M1 | 新增卡片类型注册表（core）与 `CardViewDef`（`plugin_api/ui`）；`terminal`、`file` 由 feature 登记，取代 `shared_renderers` 占位；插件 renderer 经适配层登记 | 不变 |
| M2 | `SessionTab` 增加 `card_type`；与现有布尔标志（`terminal != null`、`archived`、`plugin_renderer` 等）并存，用断言保持一致 | 不变 |
| M3 | `canGroupTarget` 与 `:3367` 的 `can_split` 改为读 `card_type` 的 `placement.split`，保留 `!closing`、`!owned_pending` 等状态条件。会话类型 `split = true`；归档 tab 在被会话记录卡片取代之前按 `split = false` 处理，结果与今天逐项相同 | 不变（用现有分组测试与一组等价性单测证明） |
| M4 | "离开组 / 拖出成独立 tab"的路径读 `placement.standalone_tab` | 不变（现有类型全为真） |
| M5 | `group_layout` 的叶子在文档与命名上从"会话身份"改称"卡片身份"；`u64` 表示与 `Snapshot` 版本 2 不变，已保存的布局不需要迁移 | 不变 |
| M6 | roster 的成员准入显式改为"会话绑定的卡片"（今天是隐含的，因为只有会话能入组） | 不变 |
| M7 | 新增窗口级浮动层作为卡片宿主的槽位；会话记录卡片（PL4b）由它承载。AI 面板在删除停靠模式之后（PL4c）也由它承载。浮动层负责 2.5.7 的全部规则：停放区域、按所属 tab 显隐、收回 / 展开动效的调用 | 会话记录见 PL4b；AI 见 PL4c |
| M8（可选，随 P5 波次 C） | 单会话 tab 在模型上也表示为"单叶分屏树"，让 `.session` owner 的 tab 与 `.group` owner 的 tab 走同一条容器代码路径 | 不变；这是内部统一，不做也不影响前面各步 |
| M9 | AI 能力移到卡片类型（2.5.8）：`CardTypeDef.ai`；`terminal`、`file`、`bmc_ikvm` 声明 `ai`；`assistantDeclared` 改为"tab 里有 AI 卡片"（含浮在该 tab 上的卡片，Q23）；上下文组装与工具可用性按卡片派生；清单级 `integration.ai`、`ai_context`、`ai_adapter_factory` 先并存再删除 | 不变（等价性单测） |
| M10（随 PL4c′） | AI 绑定统一为 tab owner：`tool_scope.Owner` 增加 `.tab`，新绑定只用 `.tab`；`.session` / `.group` 只读；`handoff` 泛化；会话日志新行 `schema = 4`；上下文机制不在这一步改动 | 不变 |
| M11（紧跟 M10；依赖 2.9 的 T1、T2） | 拉取式 tab 上下文（Q24，2.5.8）：新增 `host.tab_context`（第一个直接按 `ToolDef` 写的工具，`target = tab`、只读），参数只有 `card_refs`、`max_bytes`，返回每张 AI 卡片的身份、状态、有上限的摘要与"读细节用哪些工具"；细节由各卡片类型自己的固定 schema 工具负责（终端沿用 `host.read_terminal` / `host.search_terminal`）；`CardAi` = 摘要函数 + 工具引用；系统提示的 `<host_session_facts>` 泛化为只含元数据的 tab 清单；执行规则加调用引导；删除只在测试里使用的 `ai_session_context.zig` / `ai_group_context.zig` | **变更**：模型可见的工具与提示词变化，单独评估与回滚 |

M8 之前，"独立 tab 是单卡容器"是概念上的统一：通过一个访问函数把 `.session` owner 的 tab 看作单叶容器。把两条代码路径真正合并要动 `workspace.zig` 的主体，放在波次 C 拆分 `Workspace` 结构体时一起做才合算。

#### 2.5.6 与修订前方案的差别


| | 修订前 | 修订后 |
|---|---|---|
| 抽象 | "内容种类"，放置是 `tab / dock / float` 三选项 | "内容卡片类型"，放置约束是 `standalone_tab / split / float` 三项；没有停靠 |
| tab 与分屏 | 没有处理分屏；分组模型原样保留在方案之外 | tab 是卡片容器，分屏窗格与独立 tab 是同一张卡片的两种放置 |
| 对现有实现的态度 | 新增"卡片宿主"承载 tab、停靠、浮动三种槽位 | tab 与分屏复用现有 workspace / group / `group_layout`；卡片宿主只新增窗口级的浮动层 |
| "AI 不能作为 tab" | 一条针对 AI 的特殊规定 | `ai.chat` 的 `standalone_tab = false`、`split = false`、`float = true`，与其他类型用同一个机制；现有的停靠模式删除 |
| 入组条件 | 未涉及 | `canGroupTarget` 的硬编码条件改为读卡片类型的 `split` 约束 |
| 会话组语义 | 未涉及 | 布局（任何卡片）与 roster（仅会话卡片）分开，广播与组助手的范围不变 |
| 会话记录 | 两种内容：列表（浮动 / tab）与回放（tab） | 一种卡片 `history`，内部是列表 + 详情 |
| 为什么留在 `features/*` | 同左 | 不变：终端、会话记录、AI 仍由各自的 feature 登记卡片类型（Q3 已判定认可） |
| 浮动的范围 | 未涉及（实现上限制在所属内容区） | 标题栏以下的整个窗口（含展开的侧栏与状态栏；11-13 用户再判定，只有标题栏不可进），仍归属所属 tab，切换 tab 时收回 / 展开（2.5.7） |
| 浮动的实现 | 各浮动面板自写（AI 的 `float_model` + `ai_float_gestures`） | 通用卡片浮动层：交互是可枚举的、属于卡片，卡片类型只声明支持哪些及参数（2.5.7"实现"） |

#### 2.5.7 浮动放置：范围、归属与收回动效

> 2026-11-13 按用户判定修订。用户原话："floating 模式下，是整个window都可以拖拽停放，现在是限制在tab content里了。只是切换顶部Tab后，它们会有一个快速收回到原tab的动效。像macos的dock那个最小化一样。"

**现状（要改的地方）**

今天唯一的浮动卡片是 AI 面板，它的范围被限制在所属内容区里：

- `src/ai/float_model.zig:33-37` 的 `safeBounds(pane, window)` 取"所属窗格"与窗口的交集再内缩 8pt；`clampRect`（`:39-44`）、`resized`（`:46-61`）、`Model.rect`（`:88-97`）都基于它。最大化（`toggleMaximized`）也是铺满这个交集。
- 传入的 `pane` 是 `AiHost.ownerBounds()`（`ai_host.zig:3074-3085`）：组视图时是组的助手区域，SFTP 时是文件呈现区，其他情况是所属会话窗格；`window` 是整个视口 `(0, 0, viewport.width, viewport.height)`（`features/shell/host/nav_host.zig:585-591`）。
- `src/features/ai/pane/view/ai_float_gestures.zig` 的拖动与缩放（`:65-70` 的 `updateBounds`，`:110-137` 的 `changed`）把这两个矩形原样传给 `float_model`。
- 每个归属对象（会话或会话组）各有一份浮动呈现状态：切换 tab 时 `AiHost` 把当前的 `controller.model`（含 `visible`、`desired`、`clamped`、`restore`）存回所属对象，再取出新对象的那一份（`ai_host.zig:732-768`）。所以"浮动卡片属于某个 tab"这件事今天已经成立，只是切换时旧卡片直接消失、新卡片直接出现，没有过渡。

**新规则**

1. **停放区域是整个窗口的内容区**，不再受所属 tab content 的边界限制。浮动卡片可以越过分屏窗格、文件呈现区等边界，覆盖整个工作区。
2. **禁区**（根据代码给出的建议）：
   - **标题栏整条**（顶部 `shell_styles.title_height = 44`，`shell_styles.zig:12-13` 写明"也是原生标题栏的拖动高度"）。这一条里有：顶部 tab 条（`workspace.tabs.capsule`，`chrome_mount.zig:41-45` 把它设为 `window_region = .client`）、工具栏按钮（`toolbar.ai` 将随第七批判定删除），以及侧栏收起时移到这里的红绿灯（`shell_styles.zig:44-47`：左侧预留 14 + 52 + 6 = 72pt）。挡住它会同时挡住窗口拖动、红绿灯和收回动效的目标 tab，所以必须是禁区。
   - **侧栏**（展开时宽度为 `sidebar_width`；红绿灯展开时在侧栏头部，`shell_styles.zig:14-18` 的 `traffic_light_x/y`）。侧栏收起时，这块区域并入可停放区域。 **（11-13 用户再判定：侧栏不再是拖动禁区，卡片可以压住展开的侧栏；侧栏只从“工作区”里扣除，工作区用于最大化与默认位置。）**
   - **状态栏不是禁区（Q20 已判定）**：浮动卡片可以覆盖底部状态栏，区域下边界就是窗口底边（再内缩 8pt）。代价是卡片压住状态栏时，状态栏上的连接与路由入口（`show_connection_details`）在被压住的那段点不到；用户把卡片移开或收起即可。
   - 区域四周仍内缩 8pt（沿用 `safeBounds` 的现有值）。
   - 所以可停放区域 = 窗口内容区 − 标题栏 − 侧栏（展开时），再四周内缩 8pt。禁区只有标题栏整条与展开时的侧栏。这个矩形由 shell 计算，作为"浮动区域"交给浮动层，取代今天的 `ownerBounds() ∩ viewport`。 **更新（11-13）：拖动区域 `dragRegion` = 窗口 − 标题栏，四周内缩 8；工作区 `floatRegion` = 窗口 − 标题栏 − 展开的侧栏，内缩 8，只用于最大化与首开默认位置。**
3. **夹取规则不变，只换边界**：最小尺寸仍是 520×354（`float_model.zig:6-7`；**#52 已改为 320×354，由卡片类型的 `Descriptor.min_size` 声明**），区域放不下时取区域大小；整张卡片保持在区域内（与今天 `clampRect` 的语义相同）。最大化改为铺满浮动区域，不再是铺满所属窗格——这是随本判定一起发生的行为变化。
4. **默认位置**：~~AI 仍以所属内容区的上边缘居中为锚点计算首次打开的矩形~~（**#61 已改**：AI 首次打开从所属 tab 的 `ai.launcher` 就近展开，面板的角与图标的外角对齐，尺寸按 #52；见下文"实现"），然后按新区域夹取；`history` 卡片首次浮动时在浮动区域内居中。也就是说，"从哪里出现"仍参考所属 tab，"能停在哪里"是整个窗口。

**位置怎样记录**

- 记录**窗口内容坐标**（以窗口内容区左上角为原点的 pt），不是相对所属窗格的坐标，也不是屏幕坐标。理由：用户是相对整个窗口拖放的；切换侧栏、拖动分屏分隔条、所属窗格变化时，卡片应当停在原处，而不是跟着窗格移动。
- 沿用 `float_model` 现有的"`desired` 与 `clamped` 分离"（`:99` 的注释："边界变化只重新夹取，从不擦掉用户要求的矩形"）：`desired` 是用户最后一次放下的矩形，原样保留；`clamped` 是它在当前浮动区域里夹取后的结果，每次区域变化时重算。
- **窗口缩放**：区域变小时夹回可见区域（先缩尺寸到不小于最小值，再移位置），`desired` 不变；窗口再放大时回到 `desired`。
- **侧栏展开 / 收起、进出全屏**：都只是区域变化，走同一条夹取路径。
- **多显示器**：坐标是窗口内的 pt，与窗口在哪块屏幕、屏幕的缩放倍率无关；窗口移到较小的屏幕而被系统缩小时，按"窗口缩放"处理。不记录屏幕坐标，所以不存在"卡片停在已断开的显示器上"的情况。
- **tab 移到另一个窗口**（现有的跨窗口移交）：浮动卡片跟随所属 tab，`desired` 原样带过去，在新窗口的浮动区域里重新夹取。
- **持久化**：今天每个归属对象的浮动状态只在内存里（`AiHost` 的每归属对象存储），重启后不恢复；本判定不改变这一点。

**归属与切换 tab 时的显隐**

- 每张浮动卡片都有所属 tab：AI 卡片属于它绑定的 tab（2.5.8）；`history` 卡片属于打开它时的当前 tab。工作区没有任何 tab 时打开的 `history` 卡片属于窗口本身，不参与收回。
- **切走**：当前 tab 变为别的 tab 时，不属于新 tab 的浮动卡片按设置项选择的动画退场（默认收回到所属 tab 在顶部 tab 条上的位置，见下），结束后隐藏。卡片的视图不卸载，状态留在 view-model 里。
- **切回**：所属 tab 再次成为当前 tab 时，卡片按同一设置入场（默认从该 tab 的位置展开），回到 `clamped` 矩形（即原来停放的位置，必要时按当前区域夹取）。
- 浮动层只渲染当前 tab 的卡片（加上正在收回或展开的卡片）。

**切换 tab 时的退场与入场动画：用户可选的两种（第九批判定）**

用户原话："可以的，你可以在settings里设置，一个是带缩放回anchor的退场动画，另一款是直接fade out，带一点缩小一点点"

- **设置项**：`ui.float_card_transition`，取值 `"anchor"` 或 `"fade"`，**默认 `"anchor"`**（建议，与"浮动卡片属于所属 tab、切走时收回到该 tab"的判定最贴合，也是 Z12 第一级已经实现的效果）。
  1. **`anchor`（收向锚点）**：用 Z12 的 `AnchorTransition` 缩放并沿曲线收回到所属 tab 在 tab 条上的位置；切回时从 tab 的位置展开回原停放处。
  2. **`fade`（淡出加轻微缩小）**：原地淡出，同时略微缩小（目标 0.96–0.98，具体数值用 zenit 的 token，见下面的 Z12b）；入场时反向（从略小淡入到原大小）。
- **"减少动态效果"优先级最高**：系统或应用开启时，不论选哪一种，都退化为 zenit 的 `reduced` 行为——默认原地淡入淡出（`reduced = .fade`，0.15s），也可以由 token 设为直接显隐（`.instant`）。ZeroWork 取 zenit 默认值，不另设。
- **同一个设置覆盖所有浮动层的出入场**：浮动卡片（会话记录、AI 面板）在切换 tab 时的收回与展开；AI 浮动图标 `ai.launcher` 展开成 AI 面板、面板收起回图标的过渡（`anchor` 模式下锚点是图标本身，`fade` 模式下面板原地淡入淡出加轻微缩放、图标同时显隐）。
- **快速连续切换**：两种模式都可以中途改向，不排队（`AnchorTransition` 的 `retarget` 只翻转方向、不重置进度）。动效进行中卡片不接收输入（过渡期间节点不命中）。
- 锚点取不到时（所属 tab 被滚出 tab 条，或已关闭）：zenit 会收向 tab 条可见区域里最近的一端；从未解析到锚点时，本次退化为原地淡入淡出。所属 tab 已关闭的卡片随 tab 一起关闭，不播放动效。

**动效实现：Z12 第一级已在 zenit 上游完成（已核实）**

- zenit 仓库 `feat/app-extension-points` @ `db1fdd26`，设计说明 `docs/ANCHOR_TRANSITION.md`。**尚未同步进 ZeroWork 的 `vendor/zenit`**，使用前先按快照脚本同步（Revamp 3.5 的做法）。
- 能力：`src/ui/animation/anchor_motion.zig`（几何与时钟）、`src/ui/anchor_transition.zig`（运行时 `ui.fx.AnchorTransition` 与每窗口的锚点登记表 `Cx.motion_anchors`）。快照 + 二次贝塞尔路径 + 缩放 + 渐隐；中途改向不重置进度；锚点每帧重新解析（跟随 tab 条滚动与窗口缩放）；收起后节点 `display: none`，不占布局、不命中、不在 Tab 序与无障碍树里。
- Yix 属性：tab 条里的 tab 用 `motionAnchor` 登记锚点名；浮动卡片用 `anchorCollapsed`（是否不属于当前 tab）、`anchorTo`（所属 tab 的锚点名）或 `anchorRect`、`anchorMotion`（token）。Zig 侧是 `ui.fx.AnchorTransition.attach(...)`、`setCollapsed(...)`、`phase()`、`currentFrame()`。
- token（`anchor_motion.Tokens` 的默认值）：收回 0.28s、展开 0.32s、`ease_in_out_cubic`，减少动态效果时默认原地淡入淡出。ZeroWork 直接用默认 token，不覆盖。
- 第二级（genie 网格形变）暂不做；以后上游完成后，`anchor` 模式自动获得，不需要新的设置项。
- **`fade` 模式需要上游补一个小项 Z12b**：`AnchorTransition` 目前没有"原地淡出加轻微缩小"的预设（只有收向锚点，以及减少动态效果 / 锚点不可解析时的原地纯淡入淡出）。技术上可以把 `anchorRect` 设成"原矩形按 0.97 居中缩小"来拼出这个效果，但那是下游用参数拼动画，而且原矩形变化时不会跟随，所以不采用。登记 Z12b：在 `anchorMotion` 里加一个原地模式（例如 `mode = .fade_scale`，缩放比例作为新 token，默认取 0.97 左右），复用同一套快照、改向、减少动态效果与完成回调。Z12b 落地前，`fade` 选项先按 zenit 已有的原地纯淡入淡出执行（`reduced = .fade` 同一路径），不手写缩小。
- `AnchorTransition` 接管节点的 `display`、不透明度与命中，所以浮动层不能再在同一节点上绑 `visible`；浮动层按"是否属于当前 tab"驱动 `anchorCollapsed` 即可。

**实现：浮动由通用卡片浮动层实现（ai-panel-anchor 已落地，2026-11-13）**

> 用户判定（原话）："我觉得floating window其实就是通用card的一种状态，所有card 统一自己抽象好，而不是单独的给每个floating window做特殊处理。它的交互是可枚举的，是属于card的"

- "浮动"是卡片实例的一种放置状态（与独立 tab、tab 内分屏并列），由窗口持有的一层**通用卡片浮动层**实现；任何卡片类型都不再自写浮动逻辑。AI 面板是第一张接入的卡片，会话记录卡片（PL4b）与插件卡片按同一接口接入。
- 纯几何（无 UI 依赖）：`src/shared/base/float_card.zig`
  - `Interaction`（可枚举的浮动交互）：`move`（整窗可停放区内拖动）、`resize`（八向，最小 / 最大尺寸由卡片类型声明）、`maximize`（铺满整个可停放区 / 还原）、`raise`（按下置顶）、`close`、`fold_to_tab`（切走时收回所属 tab、切回时展开，Z12）、`open_from_anchor`（首次打开从锚点就近展开、关闭收回锚点）、`remember_position`（按卡片实例记住放下的矩形，窗口内容坐标）。`Interactions = std.EnumSet(Interaction)`。
  - `Descriptor`（卡片类型的浮动声明）：`id`、`interactions`、`min_size`、`max_size`（可空）、`default_size(content) Size`（默认尺寸公式）、`first_open`（`.center` / `.beside_anchor`）。
  - `Placement`（卡片实例的浮动状态）：`desired`（用户放下的矩形）、`clamped`（按当前区域夹取）、`maximized`、`restore`；`rect / updateBounds / setRectangle / resetPosition / toggleMaximized / closed`。
  - `floatRegion(viewport, title_height, sidebar_right)`：窗口内容区 − 标题栏（44）− 展开时的侧栏，四周内缩 8；不扣状态栏（Q20）。`clampRect / resized / defaultRect / besideAnchor`。
- 行为层：`src/shared/ui/float_card/float_layer.zig`
  - `FloatLayer`：每窗口一个（`main_window` 挂在根上，test_id `float.layer`，全窗口、pass-through、z 200）；shell 每帧 `setRegion(floatRegion)`、`setMode(ui.float_card_transition)`；`attach(scope, CardOptions)` 把卡片节点挂到层上；`raise(card)`。
  - `CardOptions`：`node`（定位节点，Z12 过渡目标）、`frame`（尺寸节点，缩放热区挂在上面）、`grip`、`descriptor`、`placement`（指向实例状态；宿主切换实例时先 `cancel()`）、`callbacks`（`close`、`rest`）、`grip_test_id` / `handle_test_ids`（AI 沿用 `ai.float.drag` / `ai.float.resize.<edge>`）。
  - `Card`：`update(origin, shown)`（每帧：夹取并写位置；关闭时不动节点，收回从原处起飞）、`rect()`、`toggleMaximized()`、`resetPosition()`（双击把手）、`close()`、`cancel()`、`present(Presentation)`、`hideNow()`、`phase()`、`presentedRect()`、`anchor_flight`（收回锚点途中，宿主据此推迟显示锚点图标）。
  - `Presentation`：`shown`、`tab`（节点里内容所属的 tab id）、`current_tab`、`explicit`（本 tab 上的显式开关 → 锚点）、`swapped`（同一节点换成了另一个 tab 的实例）、`anchor`（锚点矩形）。规则：显式开 / 关从锚点展开 / 收回锚点；所属 tab 不再是当前 tab 时收回到 tab 条上的 `workspace.tab.<id>`（`shared/base/tab_motion_anchor.zig`，tab 条渲染时用 `motionAnchor` 登记）；切回时从 tab 展开回原位；途中反向不排队；tab 已关闭则无动效直接收起；`fade` 模式与系统"减少动态效果"原地淡入淡出。
- 卡片类型注册表（PL4a，card-model 包已建立）：`Descriptor` 并入 `CardTypeDef.float`（`src/host/card_types.zig`）；AI 卡片的声明仍是 `src/ai/float_model.zig` 的 `descriptor`，经 `ai.chat` 卡片类型登记，主窗口从注册表取用。
- AI 专属的只剩：launcher 图标作为 `open_from_anchor` 的锚点（`AiHost.floatOrigin`）、AI 面板内容、"是否打开"（`model.visible`）与 AI 面板内部布局（对话区高度）。
- 动画模式：浮动层在每次开始过渡前读取 `ui.float_card_transition`（z12b 包的 `config.floatTransitionMode` + `shared/ui/styles/float_card_motion.tokens`），`anchor` 收向锚点 / 从锚点展开，`fade` 原地淡出缩小到约 0.97（Z12b `fade_scale`，不解析锚点）；系统"减少动态效果"时两者都原地纯淡入淡出。

**设置项的落点**

- **位置**：设置 › 外观与主题 › "终端与工作区"子页（`settings.appearance.aids`，`src/features/settings/model/pane_fields.zig` 的 `aids` 面板），新增一行"浮动卡片切换动画"，选项"收向所属标签"（`anchor`）与"淡出"（`fade`）。说明文字："切换顶部标签时，不属于当前标签的浮动卡片（AI、会话记录）怎样收起和展开。系统开启'减少动态效果'时一律改为淡入淡出。"
- **控件**：zenit 原生 `W.RadioGroup`（横排，默认外观），与同一外观页里"图标背景"的现有做法一致（`appearance.yix` 用 `W.RadioGroup testId="settings.field.icon_background"`）。设置的字段类型表（`pane_fields.zig:22` 的 `Kind`）里没有单选，按 `icon_background` 的先例在视图里直接挂 `RadioGroup`，不新增手搓控件。
- **配置键**：`[ui]` 段的 `float_card_transition = "anchor" | "fade"`；`config.zig` 的 `Ui` 结构（`:374`）增加枚举字段 `float_card_transition: FloatCardTransition = .anchor`，解析放在 `.ui` 分支（`:223-224`），写出放在 `[ui]` 段的写出逻辑（`:130`）。非法值返回 `InvalidValue`。
- **兼容：依赖 config-unknown-keys（已合入集成分支）**。配置解析器现在遇到未知键和未知段会跳过并告警，按原文往返保留（有上限，并做了转义校验）。所以 `float_card_transition` 按常规写出即可，不需要特殊处理：含这项修复的版本读到不认识的键会跳过并保留，保存后不会丢失。（本文基线 `f4282769` 上的 `config.zig` 还是遇到未知键就报 `UnknownKey`，行号引用以集成分支上的修复为准。）
- **生效**：保存后立即生效（下一次切换 tab 起），不需要重启。
- **test_id**：`settings.field.float_card_transition`（RadioGroup），选项 `settings.option.float_card_transition.anchor`、`settings.option.float_card_transition.fade`（zenit `RadioOption.test_id`）。

**Q15"浮动最多一张"按 tab 归属理解**

- 理解为：**每个 tab 最多一张浮动的 `history` 卡片**。因为只有当前 tab 的浮动卡片是可见的，所以任何时刻屏幕上最多一张浮动 `history` 卡片，这与原判定的观感一致。
- 与原先写法的差别（需要说明的冲突）：PL4b 原先写的是"已有浮动卡片时，再次从入口打开只把它带到前台"，那是全窗口单例。按 tab 归属后：在 tab B 从标题栏打开会话记录，而 tab A 已有一张浮动卡片时，会为 B 新建一张；A 的那张仍属于 A，处于收回状态。整个窗口里可以同时存在多张浮动 `history` 卡片（每个 tab 一张），只是同一时刻只显示一张。**Q21 已判定：按 tab 归属，每个 tab 最多一张**；不采用"全窗口单例、打开时把归属改到当前 tab"。
- AI 不受影响：每个归属对象本来就只有一份 AI 浮动状态。

**放入分屏 ⇄ 浮动（float-split，2026-11-14，用户反馈“floating window 都要有的通用 shell/chrome … 切换到 tab body 里的 card split view”）**

- 统一外框的动作顺序固定为：作为标签页打开（app-window）· 放入分屏（panel-right）· 收起 · 放大 / 还原 · 关闭（Pencil b2ghJ）。两个放置动作每张浮动卡片都有；可用性由注册表从 `placements` 推出（`card_types.floatDescriptor`：`open_as_tab` ⇔ `standalone_tab`，`dock_to_split` ⇔ `split`），卡片不另写判断；不允许时是原生 Button 的 disabled 状态，Tooltip 写原因（“会话记录不支持分屏”“AI 助手不支持作为标签页打开”）。卡片声明了注册表不允许的 `dock_to_split` 时登记失败（`CardDockToSplitNotAllowed`）。
- 放入分屏把同一个内容节点挪进所属 tab 的分屏，成为非会话卡片叶子（不是 roster 成员，M6）：单卡会话 tab 变成两卡分屏（与“向右分屏”同样生成组 tab），已是分屏时追加一个窗格；所属 tab 不能分屏、正在关闭、或再放一格就小于卡片最小尺寸时按钮置灰并说明（`model/card_dock.zig`）。
- 位置：浮动卡片中心落在 tab body 外圈 1/4 带内时放在离它最近的一边，否则右侧；新窗格放在整棵分屏树的那一边，占 1 / (n + 1)。
- 动画：anchor 模式窗格从浮动矩形展开到窗格位置（Z12）；fade 模式与减少动态效果时原地淡入。反向：窗格头部“浮动”（卡片类型允许浮动时才有）回到上次的浮动位置，anchor 模式从窗格展开。
- 放入的卡片不写进分屏布局文件；所属 tab 关闭时卡片随之关闭。非会话卡片的往返由只在 test-mode 构建里出现的测试卡片 `fixture.float` 覆盖（e2e `float_split_native`）。

**会话卡片浮动 · AI 放进分屏（cards-float，2026-11-14，用户判定“ssh类的也是可以floating的啊，AI chat也是可以放回cards layout的。”）**

- 放置：终端（本地 / SSH）、文件（SFTP）、KVM、通用会话卡片以及插件登记的所有会话类卡片 = 标签页 · 分屏 · 浮动；AI 对话 = 浮动 · 分屏（不能单独成 tab）；会话记录不变（标签页 · 浮动）。可用性只从注册表推出。会话卡片的浮动声明由 `card_types.sessionFloat` 生成：交互 = 移动 · 缩放 · 放大 · 置顶 · 关闭 · 收回到所属 tab · 记住位置（没有“收起”：会话卡片没有 launcher 可收进去），默认尺寸按 #52 的 clamp 公式（`card_types.float_sizes`：终端 / 通用会话 clamp(宽×0.55, 480, 960) × clamp(高×0.6, 300, 640)；文件 clamp(宽×0.6, 560, 1040) × clamp(高×0.65, 360, 720)；KVM clamp(宽×0.6, 520, 1024) × clamp(高×0.7, 360, 768)；min 即各轴下限）。
- 统一外框的五个动作（作为标签页打开 · 放入分屏 · 收起 · 放大 · 关闭）每张浮动卡片都显示（`float_card.HeaderAction.alwaysShown`），不支持的是原生 disabled，Tooltip 写原因（例如“终端不支持收起”）。
- 会话卡片浮动：分屏窗格头部与单卡 tab 的窗格头部都有“浮动”（原生 ghost sm + Tooltip，不能浮动时置灰写原因）。搬动同一个内容节点（`SessionTab.root`），会话照常运行；浮动卡片仍属于原 tab（单卡 tab，或所在的组 tab），切换 tab 时收回到所属 tab（Z12）。单卡 tab 的卡片浮动出去后 tab 留在标签栏上，tab body 显示空状态“卡片已浮动”与“放回标签页”；分屏里所有卡片都浮动时同样。外框里：作为标签页打开 = 回到自己的单卡 tab（来自分屏时即移出组，保留会话）；放入分屏 = 回到所属 tab 的分屏（最近一侧，规则同 float-split；单卡 tab 就是放回原位）；关闭 = 关闭这个会话（照常确认）。键盘：点在浮动卡片里即成为当前会话（搜索、右键菜单、快捷键作用于它）；浮动层的“Esc 关闭卡片”不用于会话卡片，Esc 交给终端。
- 内容节点只搬动不重建：搬动一律 `detachChildRetained` + 追加。普通 `detachChild` 会触发子树的一次性 cleanup（原生 ScrollArea 的滚动钩子随之被摘掉，滚动条停在原处的几何），只用于销毁。
- 窗格头部：放进分屏的卡片用会话窗格的同一个 Pane Header（`Workspace.mountCardPaneHeader` 与会话的 `mountPaneHeader` 共用拖动把手、浮动、更多三个部件）：拖动把手可重排，“更多” = 浮动 · 卡片自己的动作（AI：子智能体 · AI 会话列表 · 新建 AI 会话，与浮动头部的入口完全一样；子智能体 / 会话列表的弹层停靠时在“更多”按钮下方右对齐打开）· 关闭；会话事实（状态点、路径、广播、置顶）只在会话窗格上。
- 单卡 tab 放入卡片后变成的组：卡片浮动回去（或关闭）、组里只剩原来那个会话时，组还原成原来的单卡 tab（组 tab 从标签栏消失，会话不关闭）。

#### 2.5.8 AI 能力：只在卡片类型上声明，tab 能否启动 AI 由此派生

> 2026-11-13 按用户判定修订。用户原话："我感觉其实我们一个tab它下面是有n个cards的，应该是判断只要这个tab下有一个card是支持AI组装上下文的，那这个Tab就是可以启动AI的，所以应该还是只有card上有这个配置，Tab上能不能插入AI是派生的。"

**现状**

- "能否附着 AI"今天读的是**协议插件清单**，而且有三处各自的读法：
  - `AiHost.supportsAssistant`（`ai_host.zig:642-654`）：tab 必须是未归档的 `.session` owner，清单满足 `integration.ai or ai_context != null`。
  - `ai_session_context.assemble`（`features/ai/tools/host/ai_session_context.zig:6-23`）：只读 `integration.ai`；有 `ai_adapter_factory` 时由它组装，否则用清单的 `ai_context.summarize` 拼出 `provider=… session_id=… generation=…` 加摘要。
  - `AiHost.assistantToolsAvailable`（`ai_host.zig:656-669`）：会话组一律为真；单会话则检查运行状态（关闭中、失败、本机进程未运行、终端已 EOF、运行时断开、生命周期不是 attached / ready 都为假）。
- 绑定对象有两套：`tool_scope.Owner = union { session: u64, group: u64 }`（`src/ai/tool_scope.zig:6-15`）。单会话 tab 绑 `.session`，会话组 tab 绑 `.group`；会话加入组时，它的对话从 `.session` 交接到 `.group`（`session_lifecycle.zig:523-535` 的 `handoff`，只允许这一个方向，`:528`）。
- 有一套"多张卡片合并上下文"的组装代码：`ai_group_context.assemble`（`features/ai/tools/host/ai_group_context.zig:8-35`）对组里每个成员调用单会话的 `assemble`，再交给 `src/ai/group_context.zig` 的 `Context.assemble`：先为每个成员预留身份行（`session_id`、`generation`、`transport`、`available`、`name`、`cwd`），预算不够放身份就报错；剩余预算按成员平均分配；被"钉住"的成员（`group.pinned_pane`）排在最前，钉住只影响顺序，不是隐含的执行目标；最多 16 个成员（`group_context.zig:29`）。
- **但这两个推送式组装函数今天不在生产路径上（第八批判定前复核，修正本节先前的说法）**：`ai_group_context.assemble` 与 `ai_session_context.assemble` 只被测试引用（`features/ai/tools/tests/ai_local_tools_tests.zig:17`、`:577`、`:871`），插件适配器的 `assemble_context` 也只经 `ai_session_context` 调到。生产中每一轮请求的系统提示由 `AiHost` 拼出（`ai_host.zig:4346-4387`）：执行规则（`session_prompt.buildConfigured`）加一段 `<host_session_facts>`，内容是 `ai_host_queries.requestSummary`（`features/ai/tools/host/ai_host_queries.zig:28-41`）给出的**元数据**——最多 8 个会话的引用、ID、代次、协议、就绪 / 连接状态、能力标志，不含终端文本。终端、文件等**内容今天就是由模型通过工具拉取的**：`host.read_terminal`、`host.search_terminal`（`src/ai/host_terminal_queries.zig:14` 起）、`host.get_session`、`host.get_current_context`（`src/ai/host_queries.zig:101-106`，`authority = .conversation_context`）以及插件工具（`read_remote_file`、`list_remote_files`、bmc 的 `describe_frame` 等）。所以第八批 Q24 的"拉取模型"在生产里已经是现状，要做的是把它按卡片统一，而不是从推送改过来。

**新模型**

1. **AI 能力只在卡片类型上声明**。`CardTypeDef` 增加：

   ```zig
   pub const CardAi = struct {
       /// 概览摘要：为 host.tab_context 给出这张卡片一段有上限的文本（结构见本节"拉取式 tab 上下文"）；
       /// 取代清单级的 ai_context / ai_adapter_factory。细节由下面 tools 引用的工具负责。
       summary: SummaryFn,
       /// 这张卡片能作为哪些工具的目标：
       /// .session_tools —— 会话卡片：取其会话所属插件登记的工具，按该会话实际可用的服务过滤（现有 ToolBinding 的 required_services 语义不变）；
       /// .own —— 插件定义的卡片：只列本插件登记的工具 ID。
       tools: union(enum) { none, session_tools, own: []const []const u8 } = .none,  // 名称都指向统一注册表里的 ToolDef（2.9）
   };
   ```

   tab 上没有任何 AI 配置。清单级的 `integration.ai`、`ai_context`、`ai_adapter_factory` 在 PL4a 移到卡片类型上后删除（"先加后删"，5.3）。工具定义与绑定（`tool_definitions` / `tools`）仍由插件登记，因为它们与服务绑定；卡片类型只声明"自己能作为哪些工具的目标"。
2. **tab 能否启动 AI 是派生的**：tab 里只要有一张卡片的类型声明了 `ai`，这个 tab 就能启动 AI。"tab 里"包括分屏树里的卡片和浮在这个 tab 上、归属它的卡片（Q23，第 7 条）。单卡 tab 只是只有一张卡片的特例。
3. **统一绑定到 tab**：AI 对话绑定到 tab 这个卡片容器，`tool_scope.Owner` 收敛为 `tab: TabId`（`identity.zig:9` 的 `TabId`，与 `workspace_model.Tab.id` 同一个类型），不再分 `.session` 与 `.group` 两套。
4. **上下文是拉取的**（第八批 Q24 判定，设计见本节"拉取式 tab 上下文"）：模型需要时调用内置工具 `host.tab_context`，取回当前 tab 里所有声明了 `ai` 的卡片的上下文，每张卡片一条。单卡与多卡走同一套收集逻辑、返回同一种结构；预算与截断沿用 `group_context.Context` 的规则（身份先预留、剩余平均分配、16 个上限、钉住卡片只影响顺序，钉住锚点从 `group.pinned_pane` 泛化为 tab 的钉住卡片）。每张卡片的内容由它的卡片类型实现的 `CardAi.query` 按查询参数取出并组织（支持的参数见"拉取式 tab 上下文"）。系统提示里不放任何卡片内容。
5. **工具作用域**：tab 里 AI 卡片声明的工具的并集；每次调用必须显式指定目标卡片（今天组助手已经要求显式 `session_ids`，`group_context.zig` 的引导语写明"All tool calls require explicit session_ids from this frozen roster"）。目标沿用会话身份（`u64`，与分屏树叶子一致）；以后有非会话卡片声明工具时，再把目标扩展为卡片身份。调用前照旧校验目标属于冻结时的作用域（`tool_scope.Scope.validateDirectory`）。
6. **唯一事实来源**：`supportsAssistant`、`host.tab_context` 的数据源（取代只在测试里使用的 `ai_session_context.assemble`）、`assistantToolsAvailable` 都从卡片类型的 `ai` 声明派生，不再读清单字段。原先"两处门禁读法不一致"的开放问题就此消解。
7. **与放置方式无关**（第八批 Q23 判定）：一张卡片是否参与 tab 的 AI 上下文、是否让 tab "能启动 AI"，只看它的卡片类型有没有声明 `ai`，与它在 tab 里独立、分屏还是浮动无关。浮在 tab 上的卡片同样属于这个 tab（2.5.7），声明了 `ai` 就参与。
8. **运行时状态门禁保留**，按卡片逐张判断：会话关闭中、失败、本机进程未运行、终端已 EOF、运行时断开、生命周期不是 attached / ready 时，这张卡片的工具不可用，它在上下文里标为 `available=no`；对话本身保留，入口仍在（今天 `supportsAssistant` 的注释："断开或关闭中的终端必须保留 AI 对话与入口"）。tab 级的"工具可用"是"至少一张 AI 卡片的运行状态可用"。（ai-followup 包落地：`AiHost.assistantToolsAvailable` 对分屏 tab 不再一律为真，改为 `ai_tab_context.groupToolsAvailable`——组内至少一张仍在组里的 AI 卡片可用；与 `host.tab_context` 的 `available` 共用 `unavailableReason`。全部成员不可用时这一轮请求不带工具，对话与入口保留。）
9. **权限**：插件定义的卡片类型声明了 `ai`（上下文或工具），所属插件必须声明 `ai_integration` 权限（2.2 第 4 条、4.3；GLM B-2）。由 features 登记的卡片类型不属于插件，不经这条校验。
10. **AI 作用域与 roster 分开**（2.5.2）：广播仍只对会话卡片；AI 作用域是 AI 卡片。

**各卡片类型的 AI 声明**

| 卡片 | `ai` | 理由 |
|---|---|---|
| 终端 `terminal` | 有：上下文是终端内容（今天 `ai_local_tools.zig:44`、`ai_ssh_tools.zig:88` 的 `assembleContext`），工具 `.session_tools` | 与今天 local、ssh 的行为一致 |
| 文件 `file` | 有：上下文是当前目录与选择（`ai_file_tools.zig:185`），工具 `.session_tools` | 与今天 sftp 的行为一致 |
| KVM 画面 `bmc_ikvm` | 有：上下文是 bmc 清单今天的 `ai_context.summarize`，工具 `.own`（bmc 的 8 个工具） | 与今天一致；bmc 插件须声明 `ai_integration` |
| 网页 `web`（V0.5） | 由 V0.5 的设计决定 | — |
| 会话记录 `history` | **不声明**（Q22 已判定：不自动提供） | 见下 |
| AI 对话 `ai.chat` | **不声明** | 它是上下文的消费者；把自己的对话当作上下文会形成自我引用，且对话内容本来就在模型的历史里 |

**入口：每个 tab 的浮动 AI 图标（第七批判定）**

用户原话："顶部这里可能不放AI按钮了，它本来就不是全局的概念。而是floating 在tab body里，如果打开了，floating AI icon就不显示。"

- **删除标题栏的 `toolbar.ai`**。AI 不是全局入口。
- **每个 tab 有自己的浮动 AI 图标**（test_id `ai.launcher`），浮在 tab body 里，归属这个 tab；不是卡片，是浮动层上属于该 tab 的一个元素（2.5.7 的归属规则适用：只显示当前 tab 的图标）。
- **出现条件**：tab 能启动 AI 时才出现，判断沿用上面的派生规则（tab 里有声明了 `ai` 的卡片，不论放置方式；PL4a 之前用 PL1 的统一谓词）。不能启动 AI 的 tab 与空工作区没有图标。
- **与面板互斥**：该 tab 的 AI 面板打开时图标隐藏，面板收起后图标重新出现。
- **状态显示**：原来由 AI 条承担、后来计划改由 `toolbar.ai` 承担的状态，统一移到这个图标上：待审批、运行中、失败、待核实、有新回答（与今天 `ai_strip_styles.project` 的五种投影一致：`approval`、`working`、`failed`、`unknown`、`success`，`src/features/ai/cards/view/ai_strip_styles.zig:7-9`）。投影函数从 AI 条的样式文件移到 AI 的 model 层，AI 条删除后保留。
- **其余入口**：快捷键 `toggle_ai`、`@ai` 指令、右键菜单"问 AI"保留，都作用于当前 tab。
- **设计稿（已定稿）**：Pencil 区域 XqqLV「ZW · 插件化补稿 2026-11-13」。状态矩阵 tfmv1（浅色）/ cVXd5（深色）；规则 Db7OS（何时显示、状态优先级、叠加与动效）、wqZ1s（位置、拖放、分屏与过渡）；tab 上下文示意 XZGS9（单终端 c7Nk3 / yhC7U，分屏 K5PPUi / ua52Y，KVM G6wzX / Wgi3D）。导出 PNG 在 `~/work/ZeroWork-evidence/design-r2/`（11–21 号）。
- **组件与尺寸**：zenit 原生 `GlassButton` 的默认尺寸——48 的圆形、图标 24（`vendor/zenit/src/ui/components/glass_bars/mod.zig:91-92` 的 `button_image_diameter` / `button_image_size`），不覆盖尺寸与材质。
- **位置**：默认停在 tab 内容区的右下角，距右 24、距下 20。卡片自带右下角浮层时（例如 KVM 画面的帧率信息），停到该浮层上方 12。为此卡片实例需要能报告"右下角已被占用的矩形"：`CardInstance` 增加一个可选回调（例如 `corner_overlay: ?*const fn (*anyopaque) ?Rect`），bmc 的 KVM 卡片实现它；不实现的卡片视为无浮层。
- **拖动与停放**：只能在 **tab 内容区** 里拖动（与 2.5.7 浮动卡片可以覆盖整个窗口不同，图标限定在 tab 内容区），松手吸附到最近的四角之一；**所有 tab 共用一个全局位置**（记录的是"哪个角"，各 tab 按自己的内容区和浮层换算出实际坐标）。拖动中的跟手与吸附细节、位置是否跨重启保留，以 wqZ1s 为准，执行时逐条对照。
- **状态**（Db7OS 的优先级，同一时刻只显示一种）：待审批 → 运行中 → 失败 → 结果待核实 → 有新回答未读 → 空闲。待审批是唯一带着色的状态：玻璃淡着色（warning_subtle）+ warning 色图标与角点，脉冲 2 次，之后每 60s 重复一次；其余状态的图标颜色与角点、运行中的呼吸效果见 tfmv1 / Db7OS。系统"减少动态效果"开启时去掉脉冲与呼吸，只保留静态着色与角点。投影顺序与今天的 `ai_strip_styles.project`（pending > busy > failed > unknown > has_answer > idle）一致。
- **状态动效也走 zenit 原生能力**：脉冲与呼吸优先用 `GlassButton` 自身的状态与 zenit 的动画能力（keyframes / 预设）表达；如果原生没有可直接使用的"注意脉冲"，按 Z 表登记上游缺口，不在下游手写。
- **过渡**：图标展开成面板、面板收起回图标，与浮动卡片切换 tab 时遵守**同一个设置项** `ui.float_card_transition`（2.5.7，第九批）：`anchor` 模式用 Z12 的 `AnchorTransition`，锚点就是这个图标（图标用 `motionAnchor` 登记）；`fade` 模式面板原地淡入淡出加轻微缩放（Z12b）。"减少动态效果"开启时只淡入淡出。不在下游手写动画。

**会话记录卡片不自动提供 AI 上下文（Q22 已判定）**

- 收益：可以让 AI 解读一段历史输出，例如"这次部署为什么失败"。可提供的上下文是"当前选中的记录及其回放位置附近的一段"。
- 隐私：记录里可能有当时输入或打印过的秘密（口令提示后的回显、令牌、私钥片段），而且来自其他主机、其他时间；作为上下文时会随对话发给 AI 服务商。今天 AI 只会看到当前活动会话的内容，这会把可见范围扩展到历史数据。需要沿用现有的脱敏开关（`assemble` 的 `redact` 参数）。
- 预算：一条记录可能很长，进入合并上下文后会挤占同一 tab 里实时会话的预算份额（平均分配）。需要单独的上限，或只取选中片段。
- **判定**：`history` 卡片初始不声明 `ai`，不成为 tab 的上下文来源。以后做成一个显式动作："用户在会话记录卡片里选中一段，发送给当前 tab 的 AI"。它走现有的附件机制（用户主动附加的文本，`src/ai/local_text_attachments.zig` 一类），每次都由用户发起，内容只是选中的那一段，因此不涉及自动外发历史数据，也不占用 tab 上下文的预算。这个动作不在 PL4b 范围内，单独立项。
- 浮动卡片的处理见上面第 7 条（Q23 已判定：与放置无关）。原先"浮动卡片悄悄改变 tab 上下文"的顾虑由拉取模型处理：卡片内容只在模型调用 `host.tab_context` 时才发送，而且返回结果逐张标明卡片 ID、类型与放置方式，系统提示里的 tab 清单也会列出它，用户在对话的工具步骤里能看到这次读取了哪些卡片。

**从 `.session` / `.group` 迁移到 tab owner**

- **运行期**：今天单会话 tab 绑定 `.session = 会话 ID`，会话组 tab 绑定 `.group = 组 ID`。改为两者都绑定 `.tab = 该 tab 的 TabId`（单会话 tab 是它自己的 TabId；组 tab 是组 tab 的 TabId）。会话加入组时的 `handoff`（今天只允许 `.session → .group`）泛化为"把一个 tab 的对话交接给它并入的容器 tab"，冲突规则沿用（目标已有附着的对话时 `BindingConflict`，`session_lifecycle.zig:527`）。卡片离开 tab（拖出成独立 tab）时，对话留在原 tab，新 tab 没有对话；今天会话离开组时的确切行为，执行时核对并保持。
- **已保存的对话**（`ai-sessions.jsonl`，`src/ai/attached_service.zig:65`）：
  - 事实：日志里每条事件记录 owner（`session_journal.zig:23`），格式按 `schema` 版本校验（目前接受 1、2、3，`session_journal.zig:123`）；而**重启后所有对话都会被恢复为已结束的历史对话**（`attached_service.zig:80-88`：`ended = true`、`historical_environment = true`、`phase = .stopped`），没有任何绑定跨重启存活。
  - 所以不需要把旧绑定改写成 tab：旧记录里的 `.session` / `.group` owner 只用于在会话列表里显示来源。规则：日志是追加写入的，不改写旧行；`Owner` 增加 `.tab` 变体，新写入的行用 `schema = 4`；`.session` / `.group` 变体保留为**只读**，只在回放旧行时出现，`attach` 拒绝用它们创建新绑定。
  - 降级：旧版本按现有规则只接受 schema 1–3，读到 schema 4 的行会报 `InvalidSessionJournal`。这与以往 schema 升级的处理一致，写进发布说明；执行时核对旧版本遇到这个错误时是只丢 AI 历史，还是影响启动。（ai-followup 已核对：实际先报 `UnknownField`；不影响启动，但旧版本里整个 AI 不可用。ai-bugs 起新版本改写到 v4 文件名、首次启动"读旧写新"，旧版本只是看不到新对话。见 5.4。）
- **图片等附件**的 owner 是具体会话（`SessionHandle`，`session_journal.zig:9`、`:16`），表示"这张截图来自哪个会话"，不是绑定对象，不迁移。
- **入口**（第七批判定，见下）不改变上面的绑定与派生规则，只决定用户从哪里打开当前 tab 的 AI。
- **提示词文本（Q24 已判定，问题消解）**：先前担心单会话（`provider=… session_id=…`）与会话组（`assistant_group_id=…`）两种推送文本统一后会变。复核发现这两种文本只出现在测试引用的组装函数里，生产请求不使用；改为拉取后，单卡与多卡由 `host.tab_context` 返回同一种结构，不存在两种文本。golden 测试改为固定这个结构（见下）。

**拉取式 tab 上下文（第八批 Q24 判定；按"写 agent tool"的方式简化，2026-11-13）**

用户原话（Q24）："单卡和分屏卡不都是一样的收集逻辑吗？我理解是我们给到AI agent一个内置Tool，获取当前tab下的ai上下文。不是吗？"
用户澄清（总体思路）："我的核心逻辑是你要参考的是AI agent的tool编写来与各个非AI方沟通，最不济，你做一个统一的MCP，规范所有zeroWork的一些信息query，但我觉得做为一方自己内部，没必要这么麻烦，对吧？"

**原则：AI 与 ZeroWork 各个非 AI 部分之间的接口就是标准的 agent tool**

- 每个工具都是 2.9 的统一 `ToolDef`：名称、给模型看的描述、固定的 JSON schema 参数、handler、结构化结果、约定的错误结构；走同一条调用流水线、登记在同一个注册表里。今天的 `ToolDefinition` / `ToolBinding` 与 `host.Contribution` 由 2.9 的 T1、T2 收敛到它上面。
- 按"给 agent 写工具"的做法写：工具粒度清楚（一个工具做一件事）；描述写给模型看，说清什么时候用、返回什么、出错怎么办；参数尽量少，都有默认值；结果是结构化 JSON；错误信息可操作（告诉模型下一步该调用什么，例如"`CardNotInTab`：先调用 `host.tab_context` 取当前卡片列表"）。
- **一方内部不引入 MCP，也不另加协议层**。卡片类型和插件直接在进程内把自己的工具登记到统一注册表（2.9），各自只写 handler。MCP 只用于第三方或进程外扩展，与 V0.4 的定位一致（4.5、6.4 的 X-3）；`ToolDef` 的形状能一对一导出成 MCP tool，需要对外时只加适配器（2.9 第 5 条）。

**工具的划分：一个概览工具，加上各卡片类型自己的细节工具**

- **`host.tab_context`（概览）**：返回当前 tab 里每张声明了 `ai` 的卡片一条：`card_ref`、`card_type`、身份（标题、协议、主机等）、放置方式、是否可用、一段有上限的**摘要**，以及"读这张卡片的细节用哪些工具"（工具名列表）。M11 时参数只有两个，都可省略：`card_refs`（只看其中几张）、`max_bytes`（默认 8192，上限 65536）。schema 固定。
  - **查询参数（ai-followup 包，按用户要求补上）**：另加三个保留参数，都可省略、形状与 `tool_def.reserved_parameters` 一致：`max_lines`（1–500，取多少历史）、`limit`（1–200）、`cursor`（≤128 字符）；`next_cursor` 只出现在结果条目里，作为参数被 `additionalProperties: false` 拒绝。参数作用于每张选中的卡片，**每种卡片类型在自己的 `CardAi.query` 里声明支持哪些、各自含义，并自己实现取数**（`query.run`；声明了参数却没有实现，注册时 `CardQueryWithoutImplementation`）：
    - 终端：`max_lines` = 最近 N 行输出（与默认摘要同一套组装：身份、当前目录、脱敏），`limit` = 最近 N 条 shell 命令（命令文本与结束状态，来自终端命令索引 `commandHistorySnapshot`）；不支持 `cursor`（逐段续读用 `host.read_terminal` 的游标）。
    - 文件：`limit` = 远端当前目录最多 N 个目录项（默认 50），`cursor` = 从上一页的 `next_cursor` 续读；不支持 `max_lines`。
    - KVM：不支持任何参数，只给元信息（BMC 名称、视频状态、画面尺寸，不含像素），`query.note` 写明该改用 `bmc_ikvm.describe_frame` / `read_power_state` / `screenshot`。
    - 每个条目带 `params`（该卡片支持的参数名），模型据此选择。
    - **校验走统一流水线第 3 步**：给某张卡片传了它不支持的参数，返回 `Unsupported`（`message = UnsupportedParameter`），`hint` 写明哪张卡片不支持、它支持什么、本 tab 里哪些卡片支持这个参数，建议用 `card_refs` 只选它们（流水线新增 `Env.scope_hint`，工具给出的提示覆盖默认提示）。游标只能配它所属的那张卡片（省略 `card_refs` 时自动只选它），否则 `InvalidArguments`（`InvalidCursor`）。
    - **游标**：`tc1.<卡片引用 SHA-256 前 8 字节>.<偏移>.<内容修订号>`。只做定位，不授予权限（目标仍按冻结作用域校验），所以不签名；修订号对不上（目录刷新或换了目录）返回可重试的 `SnapshotChanged`，提示从头再读。分页实现自己按预算停在条目边界；结果仍被总预算截断时不签发游标，避免下一页跳过条目。
    - 不带任何查询参数时，行为与 M11 逐字相同（仍走 `CardAi.summary`）。
  - 单卡 tab 的 `cards` 只有一项；会话卡片的 `card_ref` 就是现有的 `session_ref`。
  - 摘要的预算：`max_bytes` 与全局预算（`card.contextBudget(context_window) * 4` 字节）取较小值，再按 `group_context.Context.assemble` 的规则分：先预留每张卡片的身份与状态，剩余平均分配，钉住的卡片排最前，最多 16 张。某张卡片的摘要被截断时标 `truncated: true`，并提示用它的细节工具读全文。概览本身不分页，没有游标。
  - 已结束或不可用的卡片照样列出（`available: false` 加原因），不取摘要；要读它保留下来的内容，用细节工具（例如 `host.read_terminal` 本来就能读 EOF 之后的回滚缓冲或录制）。
- **细节工具：每种卡片类型自己的、schema 固定的工具**。用户补充要求里的"多少历史""搜索""路径和深度""管理信息分类"等参数，都放在这些工具上，而不是放进 `host.tab_context`：
  - **终端卡片**：现有的 `host.read_terminal`（尾部 N 行、行范围、时间范围、命令范围、游标续取，`max_lines` / `max_bytes`）、`host.search_terminal`（搜索词、字面量或正则、大小写）、`host.list_terminal_commands`（命令索引），见 `src/ai/host_terminal_queries.zig:8-17`。不改动。
  - **文件卡片**：现有的 `list_remote_files`、`read_remote_file`、`file.read_text`（`linked_plugins.zig:109-110` 的绑定）。路径与深度这类参数如有缺口，在这些工具上补，不新开通用接口。
  - **BMC 卡片**：现有的 `read_power_state`、`read_boot`、`describe_frame`、`operation_status`，看画面仍是 `screenshot`（`always_confirm`），见 `src/plugins/bmc_ikvm/tools.zig:21-30`。
  - 新的卡片类型（例如 V0.5 网页）同样登记自己的工具。
- **"每种卡片类型自己实现 query"落到两件事**：① 提供概览摘要的函数；② 登记自己的细节工具。宿主只负责把概览拼起来、分预算、脱敏，并在调用细节工具时校验目标卡片属于当前 tab。

**`CardAi` 因此是**（`tools` / `host_tools` 里的名称都指向 2.9 统一注册表里的 `ToolDef`）：

```zig
pub const CardAi = struct {
    /// 概览摘要：为 host.tab_context 给出这张卡片的一段有上限的文本。
    summary: *const fn (ctx: *anyopaque, card: CardRef, budget_bytes: usize, redact: bool, std.mem.Allocator) anyerror!Summary,
    summary_ctx: *anyopaque,
    /// 细节工具：.session_tools 取会话所属插件登记的工具（按可用服务过滤）；.own 列本插件登记的工具；
    /// 宿主查询类工具（如 host.read_terminal）由卡片类型在这里按名字引用，以便概览告诉模型该用哪个。
    tools: union(enum) { none, session_tools, own: []const []const u8 } = .none,
    host_tools: []const []const u8 = &.{},
};
pub const Summary = struct { text: []const u8, truncated: bool, unavailable_reason: ?[]const u8 = null };
```

注册校验：`tools` / `host_tools` 引用的工具必须存在；插件定义的卡片类型声明了 `ai`，所属插件必须有 `ai_integration` 权限（2.2 第 4 条）。没有额外的参数 schema 需要校验，因为细节工具的 schema 本来就随工具注册、由现有的 `validateSchema` 检查（`plugin_tools.zig:513`）。

**防止读错数据**：只保留真正需要的那一部分。会话卡片的 `card_ref` 就是现有的 `session_ref`，它本来就绑定会话 ID 与代次，过期会被现有查询拒绝；细节工具的续取游标沿用 `host.read_terminal` 现有的游标与 `SnapshotChanged`。`host.tab_context` 自己不分页、不发游标，所以不需要新的游标认证。调用细节工具时，宿主照旧校验目标属于本次冻结的作用域（`tool_scope.Scope.validateDirectory`）。

- **系统提示里保留一份很小的"tab 清单"**（用户已确认保留，第八批）：只有卡片 `card_ref`、类型、身份、可用状态、各自可作为哪些工具的目标，不含任何内容。理由：
  1. 今天的 `<host_session_facts>` 已经是这样一份元数据（最多 8 个会话），模型靠它知道有哪些目标、该调用什么；去掉它，模型每轮都要先调用一次查询，反而多一个往返。
  2. 它不含内容，所以不增加隐私外发；体积有上限（沿用"最多 8 项"，超出时注明总数并提示调用 `host.tab_context` 或 `host.list_sessions`）。
  3. 它让"浮在 tab 上的卡片也参与"对模型可见（第 7 条）。
  做法是把 `requestSummary` 从"会话列表"泛化为"tab 里的 AI 卡片列表"，`<host_session_facts>` 改名为 `<tab_cards>` 或保留原名由执行者定。
- **审批**：读取上下文是只读操作，与 `host.read_terminal`、`host.get_session` 等现有只读查询一致：`effect = read_state`、`approval_policy = read_only`（`src/ai/plugin_tools.zig` 的默认值），不弹审批；仍受现有权限模式与"只读工具"规则约束。
- **隐私**：只有模型主动调用时才发送卡片内容。相比 2.5.8 先前设想的"每轮把合并上下文推进系统提示"，外发更少；相比生产现状（内容本来就靠工具拉取），不增加外发——概览只给每张卡片一段有上限的摘要，细节仍由模型按需调用各卡片的工具，脱敏规则相同。tab 清单只含元数据，与今天的 `<host_session_facts>` 同级。
- **token 与延迟**：需要内容时多一次工具往返（一轮模型调用加一次本地收集，本地收集是内存快照，延迟主要在模型侧）；不需要内容的问题（例如问概念、改写命令）完全不花上下文 token，比推送省。一次 `host.tab_context` 就能看到 tab 里所有卡片的概况，再按需读细节。
- **回答质量风险与缓解**：模型可能不调用工具就回答。缓解：① 执行规则（`session_prompt.zig`）加一句引导：问题涉及当前 tab 的终端输出、文件或设备状态时，先调用 `host.tab_context`（今天对 `host.get_current_context` 已有同类引导，`session_prompt.zig:49`）；② tab 清单让模型知道有内容可取；③ 用户附加的选区、`@` 引用照旧直接进入消息，不依赖模型调用。不默认"首轮自动调用一次"（用户已确认，第八批）：那等于把推送换个形式放回来，每段对话都会外发一次全部卡片内容；如果评估发现漏调用明显，再把"首轮自动调用"做成可关闭的设置单独决定。
- **与 `ai_integration`、`CardAi` 的衔接**：`CardAi.summary` 是 `host.tab_context` 的数据源，`tools` / `host_tools` 决定概览里列出的细节工具；插件定义的卡片类型声明了 `ai`，所属插件必须有 `ai_integration` 权限，否则注册失败，它的卡片不会出现在 tab 清单与概览里。
- **`host.get_current_context`、`host.get_session` / `host.list_sessions`**：分工不变。legacy 的 `read_terminal`（`src/ai/legacy_adapter.zig:152`）另行评估退役。
- **迁移与测试**：
  - 原先"上下文文本逐字不变"的 golden 测试作废，改为 `host.tab_context` 返回结构的 golden：单卡（本机、SSH、SFTP、bmc、fixture）、多卡组 tab、含断开 / EOF 卡片、含浮动的 AI 卡片、超预算截断、脱敏开启。
  - 每种卡片类型的摘要函数各有单测与 golden；bmc 的摘要不含像素。
  - 预算单测：`max_bytes` 小于、大于全局预算时取较小值；多卡平均分配与钉住顺序；截断标记与"用细节工具读全文"的提示。
  - 参数与错误单测：`card_refs` 含不属于当前 tab 的引用时返回可操作的错误；未知参数被拒绝（schema 的 `additionalProperties: false`）。
  - 注册校验单测：`tools` / `host_tools` 引用不存在的工具被拒绝；插件卡片声明 `ai` 但未声明 `ai_integration` 被拒绝。
  - 细节工具沿用现有测试，不因 M11 改动。
  - tab 清单的 golden 测试：取代 `<host_session_facts>` 的现有测试。
  - e2e：仓库里没有 e2e 断言 `host_session_facts` 的原文（grep 结果为 0）；但用模拟服务端的 AI e2e 可能检查请求里的工具列表与工具调用顺序，新增一个工具、改写清单段落后，执行者 grep 断言 `tools` 数组长度、工具名或系统提示片段的脚本逐个核对。模拟服务端回放的是脚本里写好的工具调用，不会因为多了一个可用工具就去调用它，所以现有对话流程预计不受影响（执行时确认）；另新增一条 e2e：模拟模型调用 `host.tab_context`，断言返回的卡片条目与当前 tab 一致。
- **阶段**：单独一个包 **M11**，紧跟 4c′ 的 M10。M10 是行为不变的重构；M11 新增一个工具、改写 tab 清单与执行规则，属于用户可见的 AI 行为变化，单独评估与回滚。

**简化前后对比**

| | 简化前（`e9acd990`） | 简化后 | 为什么 |
|---|---|---|---|
| 接口形态 | 自定义的 `CardQuery` 接口（`CardQueryRequest` / `CardQueryResult`），宿主分发 | 统一 `ToolDef`（2.9）：概览工具加各卡片类型自己的工具，都走同一条流水线 | 用户澄清：一方内部按写 agent tool 的方式沟通；但要有统一的接口、流水线与 schema 约定（2.9） |
| `host.tab_context` 参数 | 两层：通用参数（目标、历史范围、摘要 / 原文、上限、含不可用卡片）加 `type_params.<类型>` 扩展参数 | 只有 `card_refs`、`max_bytes`，都可省略 | 概览只需要"有哪些卡片、各是什么状态、大致内容"；历史范围、搜索、路径等细节交给各卡片的工具 |
| 历史范围、搜索、路径、管理信息分类 | 作为 `host.tab_context` 的通用 / 扩展参数 | 留在各卡片类型自己的工具上（终端：`host.read_terminal` / `host.search_terminal` 已有；文件、BMC 用现有工具） | 这些工具已存在且 schema 固定；每个工具一件事，模型更容易选对 |
| schema | 按当前 tab 的卡片类型逐次请求生成；受 schema 子集限制，扩展参数做成嵌套对象 | 每个工具一个固定 schema，随工具注册一次 | 固定 schema 更简单、可测；"不支持就报错"由 `additionalProperties: false` 自然得到 |
| 卡片参数 schema 的注册校验 | 每种卡片类型的 `params_schema` 在注册时校验、不得与通用参数重名 | 删除；细节工具的 schema 本来就随工具注册被校验 | 没有 `params_schema` 了 |
| 续取游标 | 新游标，用 `host_cursor_key` 认证，绑定 tab、卡片、代次、修订号、参数摘要 | 概览不分页、不发游标；细节工具沿用 `host.read_terminal` 现有游标 | 防读错数据靠现有的 `session_ref`（含代次）与 `SnapshotChanged` 已经够了 |
| 截断归属 | 区分 `truncated_by = card / host`，卡片收尾给游标 | 只有 `truncated` 标记加"用细节工具读全文"的提示 | 没有游标，不需要区分谁截断 |
| `host.read_terminal` / `search_terminal` | 讨论"并入统一接口还是保留并共用实现" | 它们就是终端卡片的细节工具，问题不存在 | 统一接口只做概览，不再和它们重叠 |
| 测试 | 参数校验、扩展参数、schema 生成、游标认证各一组 | 概览结构、各类型摘要、预算、错误、注册引用 | 被删掉的机制不再需要测试 |
| MCP | 未讨论 | 一方内部不用 MCP；MCP 只用于第三方或进程外扩展 | 用户澄清；与 V0.4 定位一致 |

**保留不变的用户判定**：上下文是拉取的（Q24）；系统提示保留只含元数据的 tab 清单；不默认首轮自动调用；是否参与只看卡片类型的 `ai` 声明、与放置无关（Q23）；会话记录卡片不自动提供上下文（Q22）；每种卡片类型自己实现取数（现在落在"摘要函数 + 自己的细节工具"上）。

### 2.6 "计划中"怎么表示

**方案：独立的路线条目，不是清单上的 `status` 字段。**

```zig
// src/plugins/roadmap.zig
pub const RoadmapEntry = struct {
    id: []const u8,            // "web"
    display_name: []const u8,  // "网页连接"
    target: []const u8,        // "0.5"
    design_doc: []const u8,    // "docs/DESIGN/V0.5_WEB_CONNECTION.md"
};
pub const entries = [_]RoadmapEntry{ ... };
```

规则：

1. **类型上与清单分离**。协议选择器、会话宿主、工具目录只接受 `PluginManifest`，路线条目从类型上就进不了可创建列表。这与 V0.2 §3 的既有约定一致（"仅规划的描述符单独存放，不得进入可创建列表"）。
2. **不带能力、版本号、ABI、权限**。没有实现的东西不能有"N 项能力"。设计稿 T5k96 的计划行恰好只有名称和"0.5 版本待实施"，没有能力数，也没有进入详情的箭头，与此一致。
3. **必须指向仓库里存在的设计文档**。由 check-arch（或一个单测）校验 `design_doc` 路径存在。没有设计文档的"计划"不能上界面。
4. **不会过期**。`publish` 时路线条目的 `id` 与任何已注册清单冲突即失败，所以实现落地的那个提交必须同时删掉路线条目。现有 `kvm` 计划项与 `bmc_ikvm` 并存的问题在这条规则下不会再发生。
5. 设置页的"计划中"分组显示 `display_name` 和"{target} 版本待实施"。

落地时：新增 `web` 条目；删除 `PlannedProtocol`（FTP / VNC / RDP / KVM 都没有设计文档）、`PreviewKind` 和校验示例字段（1.5 第 3 点，它们描述的流程并不存在）。

**已落地（plugin-truth 包）**：条目表放在 core 的 `src/host/plugin_roadmap.zig`（不是 `src/plugins/roadmap.zig`）——冲突校验在 core 的 `PluginHost.publish` 里做（`error.RoadmapConflict`），设置的 model 层也要读它，而 check-arch 不允许 core / model import `src/plugins`。条目多一个 `icon` 字段（设置页行的图标）。清单同时加了可选的 `summary`（设置页说明改读清单，不再按插件 ID 写死），能力目录与权限词表仍归 PL1。

**为什么不用 `status: planned`**：见 6.3-A1。"计划中"分组保留，且只列有设计文档的条目（Q1 已判定，见 6.2.1）。

### 2.7 端口与事件

插件与宿主之间的全部交互走 `src/plugin_api` 暴露的类型，分三类。

**上行端口（插件调宿主）**：沿用 `HostContext` 的 facade，按 4.3 的权限声明决定是否注入。

| 端口 | 现有实现 | 备注 |
|---|---|---|
| `connection_configs` | `host/connection_config_resolver.zig` | 只读解析已保存配置 |
| `transports` | `host/transport_factory.zig` | 为当前 owner 独立建链 |
| `credentials`、`secrets` | `host/secret_lease.zig`、`editor_credentials.zig` | 需权限 |
| `trust`（SSH 主机密钥 / TLS） | `host/tls_trust.zig` | 需权限 |
| `challenges` | `host/challenge_host.zig` | 类型化挑战 |
| `notifications` | `host/notification_host.zig` | 只提交类型化内容 |
| `tasks`、`audit`、`preferences` | `host_context.zig:13-36` | |
| `presentation`（输入租约、帧纹理） | `host/content_context.zig`、`frame_texture_sink.zig` | |
| `content`（新增） | 卡片宿主 | 打开 / 关闭本插件登记的卡片类型 |

**下行调用（宿主调插件）**：会话工厂 vtable（create / cancel / close / release_stale，现有）；内容实例 vtable（2.5）；编辑器实例 vtable（现有）；工具 handler（现有）。

**事件**：全部是类型化的、带 owner 与代次的既有通道——会话生命周期事件、通知的 publish / update、能力快照的 revision、偏好变更。**不引入通用的发布 / 订阅总线**（理由见 6.3-A6）。

**命令贡献**（PL6）：`CommandContribution { id, title, scope, required: []const ServiceKey, handler }`，并入 `actions.zig` 的目录。现在的动作 ID 是闭枚举，开放它是一项独立的改动，所以放在最后；在那之前插件不贡献命令。

**AI 工具**：沿用现有的 `ToolDefinition` / `ToolBinding`，不改。第三方工具扩展走 V0.4 的 MCP，不走插件。

### 2.8 插件 UI 怎么以 Yix 接入

**规则与 feature 完全相同**：视图 100% `.yix` + `.yss`；基础组件只用 zenit 原生；写不成 Yix 的部分逐条登记到 `YIX_EXCEPTIONS.md`；`no-inline-style`、`no-widget-internals` 两条规则已经覆盖 `src/plugins/**`（`tools/arch/rules.zon:195`、`:201`）。

**三个接入点**：

| 接入点 | 插件提供 | 宿主提供 |
|---|---|---|
| tab content | `view/content.yix` 里的主组件，参数是插件自己的 view-model；`host/` 把它包成 `CardViewDef.create` / `mount` | 槽位、焦点、主题、放置方式迁移 |
| 连接编辑槽 | `view/editor.yix` 的主组件 + view-model；`host/` 包成现有的 `EditorFactory.mount` | 向导外壳、保存事务、协议选择器、挑战界面 |
| 设置 | 默认只给 `settings_section` 字段 schema，由设置页用 zenit 原生的 Switch / Input / Select 渲染，插件一行视图代码都不写 | 行组件、保存流程 |

设置的自定义子页（`SettingsPageContribution`）不在本方案范围内：现有三个内置协议和 bmc 的偏好都能用 schema 表达，真有需求时再加。浮层同理：插件的浮层就是自己视图里的 zenit `Modal` / `Popover`，全局浮层（通知、挑战、审批）一律由宿主画，插件只提交数据（V0.2 §2 的既有边界）。

**运行期按 kind 挂载与 Yix 的衔接**：Yix 的组件组合是编译期的（`ui.view.ComponentOf(f)` 的 `f` 是 comptime 参数）。卡片宿主要在运行期按 kind 选择挂哪个内容，需要一个 Zig 写的 `CardSlot` 组件：接收运行期的 `CardInstance`，把组件给的子 scope 传给 `mount`。这是全仓唯一的一处"按注册表动态挂载"，登记为 `YIX_EXCEPTIONS` 的 (b) 类例外（本质命令式）。设置窗口已有同样形态的先例 `LegacyBody`（`features/settings/view/components/legacy_body/mod.zig`）。如果 zenit 上游愿意提供"运行期组件槽"，再收回。

**本质命令式的插件视图**：KVM 帧画面（纹理）和 V0.5 的 WKWebView 原生 surface，登记为 (b) 类例外，由用户判定；它们外面的工具栏、状态条、编辑表单必须是 Yix。

**插件目录结构**：

```
src/plugins/<id>/
  mod.zig          唯一对外门面：导出 manifest()、内容 / 编辑器的 UI 登记、init / deinit
  manifest.zig     清单字面量（纯数据 + 对 engine / host 入口的引用）
  model/           状态、规则、view-model、Intent、Ports、ids.zig（test_id 表）
  view/            .yix / .yss 及生成物、自定义 Zig 组件
  host/            实现 Ports；把视图包成宿主契约；持有纹理等原生资源
  engine/          协议栈、控制器、codec、工具 handler（不 import zenit ui）
  platform/        可选：本插件专属的 C / ObjC 桥（需声明 native_code 权限）
  tests/  preview/  acceptance/
```

`engine` 是相对 feature 多出来的一层：feature 的协议引擎在 core，而 `bundled` 插件的协议引擎只能在插件自己的目录里（例如 bmc 的 `protocol/`、`native_driver.zig`、`controller.zig`）。

### 2.9 统一工具接口（AI 与 ZeroWork 各部分之间的唯一接口）

> 2026-11-13 按用户要求新增。两句原话放在一起看："我的核心逻辑是你要参考的是AI agent的tool编写来与各个非AI方沟通，最不济，你做一个统一的MCP……但我觉得做为一方自己内部，没必要这么麻烦，对吧？"；"但虽然是一方，我们自己要有一个统一的调用和处理流程与interface和schema，不然以后也不好扩展的统一管理，特别是软件的复用抽象"。
> 结论：**一方内部不用 MCP、不加协议层；但所有工具都通过同一个 `ToolDef`、同一条调用流水线、同一个注册表、同一套 schema 约定**。每个工具本身保持简单、schema 固定。

**现状：已经有这套框架的大部分零件，但分散在三条注册路径上**

| 来源 | 定义类型 | 注册方式 | 例子 |
|---|---|---|---|
| 插件工具 | `ToolDefinition`（`id`、`version`、`description`、`schema`、`max_argument_bytes`、`validate`、`required_services`、`effect`、`approval_policy`，`src/ai/plugin_tools.zig:13-27`）加 `ToolBinding`（`:42-48`） | 清单的 `tool_definitions` / `tools`，`publish` 时 `validateBindings` | bmc 的 8 个工具 |
| 宿主查询与执行 | `host.Contribution { authority, definition }`（`src/ai/host_tools.zig:47`），`authority` 是 `ToolAuthority`（`provider.zig:28`：`session_targets`、`conversation_context`、`lifecycle`、`execution_control`、`local_network_read`） | 各文件里的 `contributions` 常量表，`AiHost.prepareHostCatalog` 收集 | `host.read_terminal`、`host.get_session`、`host.run_in_terminal` |
| 遗留适配器 | `legacy_adapter.zig` 里的 `ToolDefinition`，带 `evaluate_policy`（例如 `shellPolicy`） | 适配器 vtable 的 `tool_ids` | `run_command`、legacy `read_terminal` |

调用路径上已经有：`RequestTable.parse`（参数大小上限、JSON 解析、按 schema 校验、`validate` 钩子，`plugin_tools.zig:335-345`）、作用域校验（`tool_scope.Scope.validateDirectory`）、权限引擎（`src/ai/permission.zig`）与审批（PolicyHost、`effect` / `approval_policy`）、结构化结果（`ToolResult` 的 `status`、`ContentBlock`、`Receipt`，`plugin_tools.zig:49-52`）、审计（`src/ai/audit.zig`）与操作记录（`OperationStore`）。要做的是把三条注册路径收敛成一个，把这些步骤固定成一条流水线。

**1. 统一定义 `ToolDef`**（core，经 `plugin_api` 暴露给插件）

```zig
pub const ToolDef = struct {
    name: []const u8,              // 带命名空间：host.* / terminal.* / file.* / bmc.* / <plugin_id>.*
    version: u32 = 1,
    description: []const u8,       // 写给模型看：做什么、何时用、返回什么、常见错误怎么办
    input_schema: []const u8,      // JSON schema，受限子集（见第 4 条），固定不变
    output: OutputKind,            // 结果约定：.structured（JSON 对象）| .text | .structured_with_images
    handler: Handler,              // 只有这一项由各卡片 / 插件 / 宿主模块实现
    permission: ?Permission,       // 所属插件须声明的权限（4.3），宿主工具为 null
    approval: enum { read_only, confirm, always_confirm }, // 只读免审批 / 需审批 / 危险（沿用 ApprovalPolicy）
    effect: Effect,                // read_state / observe_image / remote_input / resource_write（沿用）
    target: union(enum) { global, tab, card_type: []const u8 }, // 作用目标
    required_services: []const services.Requirement = &.{},    // 沿用：目标卡片的会话缺这些服务时工具不可用
    budget: struct { max_argument_bytes: usize = 64 * 1024, max_result_bytes: usize = 8192, truncate: enum { tail, head, reject } = .tail },
    validate: ?*const fn (std.json.Value) anyerror!void = null, // 跨字段约束（子集表达不了的，见第 4 条）
};
pub const Handler = struct { context: *anyopaque, call: *const fn (*anyopaque, ToolCall, std.mem.Allocator) anyerror!ToolOutput };
```

现有三种定义都是它的子集：`ToolDefinition` 缺 `target` / `output` / `budget`（取默认值即可），`host.Contribution` 的 `authority` 映射到 `target` 与权限检查，遗留适配器的 `evaluate_policy` 是审批步骤里的一个钩子。

**2. 统一调用流水线**（所有工具走同一条路径，各模块只实现 handler）

1. **解析**：按工具名找到 `ToolDef`（名称经现有的 `encodeName` 与提供方安全名互转，`plugin_tools.zig:109`），参数大小上限，JSON 解析。
2. **schema 校验**：按 `input_schema` 校验，再跑 `validate` 钩子。失败返回 `InvalidArguments`，附出错字段。
3. **作用域与权限**：`target` 为 `tab` / `card_type` 时，目标必须属于本次冻结的作用域（`validateDirectory`），卡片类型匹配，所需服务可用；`permission` 已被所属插件声明（注册期已保证，这里再断言）。
4. **审批**：按 `approval` 与 `effect` 交给现有的权限引擎与 PolicyHost；`evaluate_policy` 一类的细粒度策略作为这一步的钩子。
5. **分发**：调用 `handler`。
6. **结果规范化**：handler 返回 `ToolOutput`，流水线统一包成 `ToolResult`（状态、结构化内容、图片引用、回执），错误统一成第 4 条的错误结构。
7. **脱敏与预算截断**：统一跑脱敏（与今天 `redact` 同一规则）；超过 `budget.max_result_bytes` 按 `truncate` 处理并标 `truncated`。
8. **审计与执行记录**：写 `audit.Log` 与 `OperationStore`（有副作用的工具），记录工具名、版本、参数摘要、目标、审批结论、结果状态。
9. **返回**给模型。

**3. 统一注册**

- 一个注册表 `ToolRegistry`，在组合根里与插件注册表同时构建、两阶段校验、发布不可变快照（与 `publish` 同一模式）。登记来源只有三种，都走同一个 `register(ToolDef)`：宿主模块（`host.*`）、feature 登记的卡片类型（`terminal.*`、`file.*` 等）、插件清单（`<plugin_id>.*` 或插件自定义卡片的命名空间）。
- 卡片类型的 `CardAi.tools` 只引用已注册的 `ToolDef` 名称（2.5.8）。
- 每次请求的工具表（今天的 `RequestTable`）从这个快照里按作用域筛出来，不再分别拼三个来源。

迁移分三步，**都排在 M11 之前或与之衔接**：

| 步骤 | 内容 | 行为 | 与其他阶段的关系 |
|---|---|---|---|
| T1 | 定义 `ToolDef`、`ToolRegistry` 与流水线；三种现有定义各写一个适配器登记进注册表（`ToolDefinition` + `ToolBinding`、`host.Contribution`、遗留适配器的工具）；`RequestTable` 改为从注册表筛选 | 不变（工具名、schema、审批、结果逐项相同，有等价性测试） | 随 PL3（`plugin_api` 暴露 `ToolDef`）；早于 M11 |
| T2 | 宿主查询与执行工具（`host_queries`、`host_terminal_queries`、`host_execution` 等）与插件工具改为直接写 `ToolDef`，删掉对应适配器；补齐 `target`、`output`、`budget` | 不变 | 随 PL4a 的 M9（卡片类型开始引用工具）；早于 M11 |
| T3 | 遗留适配器的 `run_command` 与 legacy `read_terminal` 迁成 `ToolDef` 或退役（legacy `read_terminal` 与 `host.read_terminal` 重叠，倾向退役，需评估模型行为影响） | 迁移不变；退役是变更，单独评估 | 与 M11 无依赖，可在其后 |
| M11 | `host.tab_context` 是**第一个直接按 `ToolDef` 新写的工具**（`target = tab`、`approval = read_only`），各卡片类型的摘要函数作为它的数据源 | 变更（2.5.8） | 依赖 T1、T2 与 M10 |

MCP 相关的 `host.mcp_*` 工具（调用第三方 MCP 服务器）本身也是一方工具，同样登记为 `ToolDef`；它们代理的第三方工具不进这个注册表。

**4. 统一 schema 约定**（只写一次，全部工具共用，注册期强制）

| 约定 | 内容 |
|---|---|
| 命名 | 工具名 `命名空间.动词_对象`（例如 `terminal.read`、`host.get_session`），小写加下划线；参数名小写加下划线 |
| 目标 | 卡片 / 会话用字符串引用：`card_ref`（会话卡片即 `session_ref`）；多目标用数组，上限 16 |
| 上限 | `max_bytes`、`max_lines`、`limit` 三个保留名，类型与取值范围固定（即今天 `host_terminal_queries.zig:10-12` 的片段） |
| 分页 | 请求用 `cursor`，响应给 `next_cursor`；`cursor` 与范围字段互斥 |
| 时间范围 | `start_ms` / `end_ms`，配 `time_basis` 枚举（沿用 `host_terminal_queries.zig:9`） |
| 默认值 | 每个可选参数都有默认值，写在 `description` 里（子集允许 `default` 关键字，但校验器不据此补值，由 handler 落实） |
| 错误 | `{ code, message, retryable, hint }`；`code` 用一张共享枚举（`InvalidArguments`、`TargetNotAuthorized`、`CardNotInTab`、`SnapshotChanged`、`RangeUnavailable`、`Unsupported…` 等）；`hint` 告诉模型下一步可以调用什么 |
| 顶层对象 | 输入必须是对象，`additionalProperties: false`，所以"不支持的参数就报错"对所有工具自动成立 |

这些约定以一组**共享 schema 片段**（Zig 常量，今天 `host_terminal_queries.zig` 里的 `bytes`、`lines`、`pages`、`ranges` 就是这种写法）加上**注册期检查**落实：`register` 时先用现有的 `validateSchema`（`plugin_tools.zig:513`）检查子集，再检查名称格式、顶层 `additionalProperties: false`、保留参数名的类型与范围是否与共享片段一致。

现有校验器的局限（`plugin_tools.zig:524` 的允许关键字只有 `type`、`properties`、`required`、`additionalProperties`、`items`、`minItems`、`maxItems`、`uniqueItems`、`minLength`、`maxLength`、`minimum`、`maximum`、`enum`、`description`、`default`、`title`）：没有 `oneOf` / `anyOf` / `allOf`、`$ref`、`pattern`、`format`。因此字段之间的约束（例如 `cursor` 与范围字段互斥）放在 `validate` 钩子里；输出结构不经这个校验器，由 handler 的 Zig 结果类型保证，并用 golden 测试固定。不为此引入完整的 JSON Schema 实现（MCP 那边另有校验器 `mcp_schema.zig`，只用于第三方 MCP 的 schema，不混用）。

**5. 可以一对一导出为 MCP tool，但内部不依赖 MCP**

- 映射：`name` → MCP 工具名（命名空间里的点经 `encodeName` 转成安全名）；`description` → `description`；`input_schema` → `inputSchema`（受限子集本身就是合法的 JSON Schema）；`approval` / `effect` → `annotations`（`read_only` 对应 `readOnlyHint`，`always_confirm` 或 `resource_write` 对应 `destructiveHint`）；`ToolOutput` 的结构化内容 → `structuredContent`，文本 → `content`；错误结构 → `isError` 加错误内容。
- 对外暴露时（V0.4 的进程外 MCP，或以后开放给第三方）只需要加一个"注册表快照 → MCP server"的适配器，调用仍走同一条流水线，审批与权限仍在宿主一侧执行，不依赖 MCP 客户端的提示。
- 内部任何地方都不经过 MCP 序列化。是否对外暴露、暴露哪些工具，是另一项需要用户决定的工作，不在本方案内。

**6. 简化与统一：为什么两者不冲突**

- **删掉的是"每个工具里的复杂度"**（上一轮）：`host.tab_context` 的两层参数与按类型嵌套的扩展参数、按 tab 逐次生成的 schema、新的游标认证、自定义的 `CardQuery` 接口——都不再需要，因为每个工具只做一件事、schema 固定，细节交给各卡片类型自己的工具。
- **新加的是"所有工具共用的一层框架"**（这一轮）：一个 `ToolDef`、一条流水线、一个注册表、一套 schema 约定。它不是新的协议层，而是把今天已经存在、但分散在三条注册路径上的零件收敛成一处。
- 两者方向一致：工具越简单，越容易用同一个框架统一管理；框架越统一，单个工具就越不需要自带校验、审批、截断、审计这些横切逻辑。各卡片和插件只写 handler。

---

## 3. 分层与 check-arch

### 3.1 插件放在哪一层

```
platform ← core ← plugin_api ← plugins/<p>/{model, engine} ← plugins/<p>/view ← plugins/<p>/host ← plugins/index ← app
                       ↑                                                                                  
                 features/*（经注册表快照消费插件，不 import 插件）
```

- **`src/plugin_api/`（新层）**：插件能 import 的唯一宿主面。分两个文件组：`mod.zig`（不 import zenit `ui`：清单、贡献、能力、权限、端口类型、服务键、身份类型）和 `ui.zig`（内容 / 编辑器的 UI 契约，import zenit `ui`）。它内部再导出 core 里的既有类型，不重写实现。
- **API 面的范围与 `host_api_minor`**（GLM C.f）：凡是从 `plugin_api/mod.zig`、`plugin_api/ui.zig` 可达的公开声明（包括再导出的 core 类型及其公开字段）都算 API 面。core 改名或改字段，只要穿透到这两个文件，就是 API 变更：只加不删的变更递增 `host_api_minor`，删除或改语义的变更递增主版本。用一个快照单测落实：枚举这两个文件可达的公开声明名与字段名，与仓库里的快照文件比对，有差异就要求同一提交里更新快照并改版本号。
- **`src/host/plugin/`（core）**：注册表、能力目录、校验。不 import `ui`，不 import 任何插件。
- **`src/plugins/index.zig`**：组合根，取代 `linked_plugins.zig` 与 `application_plugins.zig`。只被 `src/app/**` import。
- **`src/plugins/<p>/`**：按 2.8 的结构分层。

**为什么要单独一层 `plugin_api`，而不是让插件像 feature 一样直接 import core**：

1. 插件的 API 面变成一个可以逐行审阅的文件列表。今天 bmc 直接 import `src/host` 下 19 个文件、`src/ai` 4 个、`src/config` 2 个、`src/proto/ssh` 2 处、`src/platform` 1 个，还有 `features/` 内部 4 处（对 bmc 非测试代码的 import 统计）。
2. 4.3 的权限模型要靠"插件够不到 facade 之外的东西"才成立，这只能用 import 规则落实。
3. `plugin_ui_contract.zig` 目前在 core 里 import `ui`，是基线里的 `layer:core->zenit_ui` 违规；把 UI 契约挪到 `plugin_api/ui.zig` 正好清掉它，同时清掉 `wizard.zig`、`workspace.zig` 两条 `layer:view->core`（已核实：`tools/arch/baseline.txt:843`、`:978`；GLM B-9 说基线里查不到，是它只看了 `view->legacy_plugin` 那一段）。

### 3.2 import 规则

| 来源 ↓ / 目标 → | std | zenit `ui` | shared/base | shared/ui | plugin_api | 本插件 model / engine | 本插件 view | 本插件 host | core | platform | features | 其他插件 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 插件 model | 可 | 否（`view_model.zig` 仅响应式子集） | 可 | 否 | `mod.zig` | 可 | 否 | 否 | 否 | 否 | 否 | 否 |
| 插件 engine | 可 | **否** | 可 | 否 | `mod.zig` | 可 | 否 | 否 | 仅内置级 | 仅本插件 `platform/` | 否 | 否 |
| 插件 view | 可 | 可 | 可 | 可 | 否 | model | 可 | 否 | **否** | **否** | 否 | 否 |
| 插件 host | 可 | 可 | 可 | 可 | 全部 | 可 | 可 | 可 | 仅内置级 | 仅本插件 `platform/` | 否 | 否 |
| 插件 `mod.zig` / `manifest.zig` | 可 | — | 可 | — | 全部 | 可 | — | 可 | 仅内置级 | 否 | 否 | 否 |
| `plugins/index.zig` | 可 | 可 | 可 | — | 全部 | — | — | — | 可 | — | 仅 `mod.zig` | 仅 `mod.zig` |
| core | 可 | 否 | 可 | 否 | 否 | **否** | 否 | 否 | 可 | 可 | 否 | **否** |
| features/* | 按现有矩阵 | | | | `ui.zig` 的槽位类型（host 层） | **否** | 否 | 否 | 按现有矩阵 | | | **否** |
| app | 可 | 可 | 可 | 可 | 可 | — | — | — | 可 | 可 | 仅 `mod.zig` | 仅 `index.zig` |

"内置级"指 `origin = .builtin` 的插件（local、ssh、sftp）。它们是对 core 里既有引擎的适配器，需要 import core；`bundled` 插件不允许。每个插件的级别写在 `rules.zon` 的一张表里，并用一个单测保证它与清单的 `origin` 一致。

**内置级的"双 API 面"要如实承认，并且只降不升**（GLM B-15）：local、ssh、sftp 能直接 import core，例如 `plugins/ssh/connection_source.zig:8` 直接 import `config/credential_store.zig`。所以"插件的 API 面可以逐行审阅"这个承诺对这三个最敏感的插件不成立，它们的 API 面就是 core。落实办法：内置级插件文件归到单独的层（例如 `plugin_builtin_*`），它到 core 的 import **不放进** `allow`，而是在规则上线时整体进基线。于是现有的 core import 都成为可数的基线条目，新增一条就是新违规，必须在评审里说明；能经 `plugin_api` 完成的新代码一律走 `plugin_api`。这样不需要给 check-arch 加新机制，用的是现有"基线只降不升"的做法。

三点补充：

- **features 不 import 插件**，连门面也不行。features 通过注册表快照、服务访问接口、卡片宿主消费插件。今天 `features/ai` 直接 import bmc 的工具与输入模块，要改成经类型化服务（bmc 已经登记了 console、framebuffer、remote_input 服务定义，`plugins/bmc_ikvm/plugin.zig:121`）。
- **插件不 import features**，连门面也不行。需要的共享界面件来自 `shared/ui`。bmc 现在 import 的 `features/shell/view/shell_styles.zig` 等要么下沉到 `shared/ui`，要么由宿主经槽位提供。
- **`plugins/remote/` 归位到 `features/connections/wizard`**。它是 SSH / SFTP 共用的连接编辑器，本来就属于 connections；清单用现有的 `EditorFactory.shared_editor` 字段引用它（`plugin_ui_contract.zig:71-77`）。

### 3.3 新增的 check-arch 规则

**先说清现有工具能表达什么**（核实了 GLM B-1、B-6、B-7）：

- 层判定先看矩阵，矩阵放行后才看跨 feature（`tools/arch/rules.zig:217-226`）；跨 feature 只在目标路径匹配到 `{feature}` 段时才判断，而且 `facade` 层对跨 feature 放行（`rules.zon:170`）。
- 今天 `src/plugins/{feature}/{model,view,host}/**` 与 features 用的是**同一组层名**（`rules.zon:70-76`），所以 features 的 host import 插件的 host 是 `host -> host`，矩阵放行，只剩跨 feature 能拦；而 features import 插件的 `mod.zig` 是 `facade`，跨 feature 也放行。也就是说，现有机制拦不住"features import 插件门面"。
- 标识符规则只有 `name`、`files`、`forbid` 三个字段（`rules.zig:26-32`），命中就记违规，没有按文件的例外（`check_arch.zig:233-243`）。`findSequence` 只匹配**标识符**与 `.` 交替的序列（`scan.zig:91-112`），因此关键字 `extern`、内建函数 `@cImport` / `@extern`、字符串字面量 `"bmc_ikvm"` 都匹配不到。这一点 GLM 只指出了字符串字面量，复核时发现 `extern` 与 `@cImport` 也一样。
- `std.Io.net` 是真实存在的路径（例如 `host/connection_config_resolver.zig:113`，全仓 11 个文件使用），GLM 对它是否存在的疑问不成立。

据此修订后的规则：

| 规则名 | 内容 | 实现方式 |
|---|---|---|
| `layer:*`（矩阵扩展） | 3.2 的矩阵：新增 `plugin_api`、`plugin_engine`、`plugin_index` 三层；**插件目录改用独立的层名**（`plugin_facade`、`plugin_model`、`plugin_view`、`plugin_host`、`plugin_tests`，内置级另加 `plugin_builtin_*`），不再与 features 共用 `facade / model / view / host` | `rules.zon` 的 `layers` 与 `allow`，现有机制即可 |
| `plugin-tier` | `bundled` 插件的任何层 import core 或 platform 即违规；内置级到 core 的 import 进基线、只降不升（3.2） | 同上：级别体现在层名上，不需要新机制 |
| `no-plugin-import` | core 与 features 的代码（含测试）import `src/plugins/**` 即违规；只有 `src/app/**` 可以 import `plugins/index.zig` | **改为纯矩阵规则**（GLM B-7）：`core`、features 各层的 `allow` 里不出现任何 `plugin_*` 层。违规名形如 `layer:host->plugin_host`，退出标准按这些新名字写；过渡层删除后旧名 `layer:*->legacy_plugin` 自然消失 |
| `ident:no-plugin-id-branch` | core / features / shared / app 的非测试代码里出现已注册插件 ID 的字符串字面量，或出现 `LegacyPluginId` / `PluginId` 标识符，即违规。允许名单：兼容 codec（`config/connection_envelope.zig`）与 `plugins/index.zig` | 分两步（GLM B-1 的方案二，加工具扩展）：① 标识符部分用现有机制立即上线；② 字符串部分需要给 `IdentRule` 加 `forbid_strings`（按字符串字面量的值匹配）与 `allow_files`，约 30–50 行工具改动加 `tools/arch` 自己的单测，随 PL3 第 8 步做。只禁"字面量等于某个插件 ID"，不禁比较函数，所以日志与资产名里不等于插件 ID 的字面量不会误报；测试块照旧跳过 |
| `ident:plugin-raw-io` | `bundled` 插件的非测试代码出现 `std.posix`、`std.process`、`std.c`、`std.Io.net`、`std.Io.Dir`、`std.Io.File`、`std.DynLib`，以及关键字 `extern`、内建 `@cImport`、`@extern`，即违规。例外按权限分：`native_code` 只豁免 `extern` / `@cImport` / `@extern`；`plugin_data` 只豁免宿主交给它的目录句柄上的文件操作（4.4）。`@embedFile` 不禁：它是编译期把仓库内文件嵌入，不是运行期 IO | 标识符部分用现有机制；关键字与内建需要让 `findSequence` 接受非标识符 token（与上一条同一次工具扩展）；每插件例外表用一个单测保证与清单 `permissions` 一致 |
| `ident:no-dylib`（新增，GLM C.d） | 全部 `src/**` 的非测试代码出现 `std.DynLib`、`dlopen`、`dlsym` 即违规，没有例外（今天全仓零命中，上线时基线为 0） | 现有标识符机制即可（都是标识符）。`.c` / `.m` 源不在扫描范围内，由 4.3 的审计 checklist 覆盖 |

另有两项数据校验并入 `check-arch` 的第三个子命令或单测：`roadmap.zig` 每个条目的 `design_doc` 路径存在；`build.zig` 里登记到插件目录下的 C / ObjC 源，其所属插件的清单必须声明 `native_code`（GLM B-6）。

已核实的现状样本（`ident:plugin-raw-io` 上线后进基线的）：`bmc_ikvm/management_journal.zig:85` 的 `std.c.fsync`；`observation_image.zig:98` 起 11 个 `extern "c"` CoreGraphics 声明；`protocol/tls.zig:7-16` 的 `extern fn zw_bmc_tls_*`。

所有新规则都按现有做法"先进基线、只降不升"：规则上线的那个提交重建基线并在提交说明里写明各规则的条数。

### 3.4 现有过渡条目怎样清零

| 基线类别（条数） | 清零手段 | 阶段 |
|---|---|---|
| `layer:core->plugin_registry`（1）、`layer:plugin_registry->host`（3）、`layer:host->plugin_registry`（1）、`layer:tests->plugin_registry`（2） | 组合根改为 `plugins/index.zig`，由 app 构造注册表后注入 `SessionHost`；`session_host.zig:363` 不再自己拉组合根 | PL3 |
| `layer:core->legacy_plugin`（7） | `ai/*` → bmc 的 import 挪到 bmc 自己的测试；`local/adapter.zig` → `plugins/local/config.zig` 的类型下沉到 `src/local` | PL3 |
| `cross-feature` 中 features ↔ `plugins/remote`、`layer:host->legacy_plugin` 中 connections 相关 | `plugins/remote/` 归位 `features/connections/wizard` | PL3（跟随 P5 波次 A 的 connections） |
| `layer:host->legacy_plugin` 中 `features/ai` → bmc（8）、→ ssh（1） | 改经类型化服务与工具绑定，不 import 插件文件 | PL3 |
| `layer:view->legacy_plugin`（6）、workspace / terminal → `plugins/ssh/*` | ssh 的 `connect_job`、`runtime_binding`、`terminal_service` 是对 core 引擎的适配，按使用方下沉到 `src/host` 或留在 ssh 插件内并经服务访问 | PL3 / PL4a |
| `layer:legacy_plugin->view`（12）、`->host`（4）、`->model`（1）、bmc ↔ features 的 `cross-feature` | bmc 分层（engine / model / host），共享样式改用 `shared/ui` | PL3（分层）、PL5（视图） |
| `ident:no-inline-style`（5）、`ident:no-widget-internals`（4） | 插件视图 Yix 化 | PL5 |
| `rules.zon` 的过渡层 `legacy_plugin`、`plugin_registry` 及 `allow` 中对它们的放行 | 上面全部清零后删除，同时删除 `rules.zig` 里两个过渡测试 | PL5 结束 |

---

## 4. 安全模型

### 4.1 前提与威胁

前提有两条。第一，用户把 ZeroWork 本身当作不可信的第三方仓库，先审计再执行。第二，应用进程里有高价值资产：钥匙串 vault（同一 scope 的全部密码、API Key、私钥口令、TOTP 种子集中在一个钥匙串项里，V0.2 §4.2.2）、活跃的 SSH 会话、对远端的输入能力、AI 的密钥。

| 威胁 | 现实程度 | 本方案的应对 |
|---|---|---|
| 恶意的第三方插件作者 | 取决于是否开放第三方插件 | 不开放运行期加载；外部代码只能经审计后 vendoring（T2） |
| 插件代码在审计之后被替换 | 运行期加载才有 | 编译期链接：运行的代码 = 被审计的那个 commit |
| 第一方插件的 bug 越权访问（读到别的会话的凭据、写错文件） | 高 | facade 只注入已声明的权限；owner / 代次校验（现有）；check-arch 的 `plugin-raw-io` |
| 插件解析恶意远端数据（RFB 帧、Redfish JSON、JPEG、网页内容）时被利用 | **高，且是当前最现实的一条** | 有界解析与帧预算（现有 `frame_budget`）；解析器的模糊测试；用户可以禁用不用的 `bundled` 插件，让它的解析器根本不被调用（Q5，PL1 / PL2）；把高风险解析器移到进程外登记为独立项（6.4 的 X-2），不再写成"有证据后再说" |
| AI 被提示注入后调用插件工具 | 中 | 现有的 PolicyHost 效果分类 + 审批；不因插件化放宽；向 AI 暴露工具必须声明 `ai_integration` 权限（4.3）；禁用插件后它的工具从目录里消失（Q5） |
| 测试夹具进入生产包 | 低 | `build.zig:24` 已有的 panic 守卫，保留 |

### 4.2 信任级别

| 级别 | 来源 | 加载方式 | 可 import | 现有成员 |
|---|---|---|---|---|
| T0 内置（`builtin`） | 本仓库 | 编译期 | core + plugin_api | local、ssh、sftp |
| T1 随应用提供（`bundled`） | 本仓库 | 编译期 | 仅 plugin_api（+ 本插件 `platform/`） | bmc_ikvm；将来的 web |
| T2 外部源码（暂不实现） | 第三方源码，经用户审计后以固定 commit vendoring 进仓库 | 编译期 | 与 T1 相同，lint 更严（不允许 `native_code`） | 无 |
| T3 运行期加载 | 第三方二进制 | 运行期 | — | **不做** |

T2 只是给将来留的位置：机制上它与 T1 相同（同一套清单、同一套 import 规则），区别只在来源展示和更严的 lint。本方案不为它新增 `Origin` 变体，等真有第一个 T2 候选时再加。

### 4.3 权限声明与落实

**词表**（固定枚举，初稿，PL1 定稿）：

| 权限 | 含义 | 对应的宿主 facade / 例外 |
|---|---|---|
| `network_via_host` | 经宿主的传输工厂建链 | `HostContext.transports` |
| `credentials` | 解析已保存的凭据引用 | `credentials`、`secrets`（`host.secrets`） |
| `tls_trust` | 读写 TLS 信任 / pin | `trust.tls`（`host.tls_trust`） |
| `ssh_host_keys` | SSH 主机密钥校验 | `trust.ssh_host_keys` |
| `remote_input` | 向远端发送键鼠输入 | 输入租约 |
| `frame_surface` | 发布画面帧 | `presentation.frame_sink`（`host.frame_budget`） |
| `resource_write` | 远端管理写操作（电源、启动项） | `resource_actions`（`host.resource_actions`） |
| `local_process` | 启动本机进程 | 仅 T0 |
| `local_files` | 访问用户选择的本地路径 | 文件选择 facade |
| `plugin_data` | 在应用数据目录下持久化自己的数据 | 每插件子目录（4.4） |
| `native_code` | 链接本插件的 C / ObjC 代码 | check-arch 例外；**等于没有边界**，见下 |
| `ai_integration` | 向 AI 暴露工具（接受 AI 发起的调用），或提供会话摘要（`ai_context`，内容会随对话发给 AI 服务商） | 工具目录登记；注册校验见 2.2 第 4 条。真正的动作级门禁仍是工具的效果分类与审批 |

**落实方式有三层，都不是沙箱**：

1. **注入**。`HostContext` 的 facade 今天就全是可空指针（`host_context.zig:39-55`），由宿主工厂填。改为：工厂只填清单 `permissions` 覆盖到的 facade，其余保持 `null`。没声明 `credentials` 的插件拿到的 `secrets` 就是空的。这一层是真实的 API 级约束，并且可以写单测（"未声明权限 → facade 为空"）。
2. **注册校验**。`dependencies` 里的敏感宿主 API（`host.secrets`、`host.tls_trust`、`host.resource_actions`、`host.frame_budget`，见 `linked_plugins.zig:10-18`）必须被 `permissions` 覆盖，否则 `publish` 失败。
3. **静态规则**。`plugin-tier` 让 `bundled` 插件够不到 core 的内部；`plugin-raw-io` 禁止它绕过 facade 直接用系统调用；例外表必须与清单权限一致。

**`native_code` 等于没有边界**（GLM B-14，写成显式条款）：插件的 C 源由 `build.zig` 直接编进主程序（`build.zig:1053-1061` 的 `addBmcNative`，`:72` 把它挂在 `core` 模块上），与应用同进程、同签名身份，可以直接调用 Security.framework 读写钥匙串（钥匙串实现走 `config/credential_store.zig` → `platform/keychain.zig`，也在同一进程）。上面第 1 层的 facade 注入只约束 Zig 侧经 `HostContext` 的访问，约束不了 C 符号。所以对声明了 `native_code` 的插件，其余权限声明都只有文档意义；审阅时应当按"它能做进程能做的一切"来审。

**审计 checklist**（GLM C 节）：下面三条的依据是 V0.2 已有的规定"新库链接、平台权限或公共 API 缺口须显式列为基础设施变更"（`V0.2_PLUGIN_HOST.md:30`）。**写进 `AGENTS.md` 这一步暂缓（Q19，用户这次未选）**，三条内容先留在本文，作为评审插件相关提交时的参照：
1. 新增或修改插件目录下的 C / ObjC 源、`build.zig` 里的 C 源清单、链接的系统库与 framework，属于基础设施变更，必须单独评审，不能夹在功能提交里。
2. 新增或扩大任何插件的 `permissions`，提交说明必须列出新增的权限与理由。
3. `vendor/` 下新增或升级第三方源码（例如 mbedtls、zlib），按不可信第三方代码处理：固定版本，记录来源与哈希。

如果以后决定写进 `AGENTS.md`，需要用户同意，并单独一个提交；在那之前它不是仓库的强制准入规则，只是本方案的建议。

**展示**：设置页的"权限"行从 `permissions` 生成文案，取代 `settings_plugins.zig:86-91` 的按 ID 分支。权限行下固定显示一句"以上是声明性约束，不是授权门禁"（措辞以 PL1 的设计确认为准）。这一句列为 PL1 的退出标准，并有单测断言（GLM C.e 的条件一）。

**授权提示**：编译期链接的第一方插件没有"安装"这个时刻，做一个"是否授予权限"的对话框只是摆设。真正起作用的授权点已经存在，并且都是动作级的：

- AI 工具的效果分类与审批（`src/ai/plugin_tools.zig:9-12`：`read_state` / `observe_image` / `remote_input` / `resource_write`；`read_only` / `confirm` / `always_confirm`）。
- 连接时的挑战（凭据输入、主机密钥、TLS 信任）。
- macOS 自身的权限提示。

本方案不新增安装期或首次使用的授权弹窗。用户缩小攻击面的手段是禁用不用的 `bundled` 插件（Q5 已判定要做，设计见 6.2.1）。

**必须写在文档和界面里的一句话**：受限 facade 加静态规则是架构约束，防的是第一方代码的误用和越界，**不是对恶意进程内代码的隔离**。这与 V0.2 §8.2 的原话一致（`V0.2_PLUGIN_HOST.md:339`）。

### 4.4 数据隔离

- 凭据：沿用现有机制——清单的 `credential_references` 回调给出引用，宿主按 owner 授权，单次上限 16 个（`src/host/plugin_security_host.zig`）。
- 插件自有数据：今天 bmc 的管理日志直接写在应用数据根目录（`application_plugins.zig:38` 的 `bmc-management-v1.json`）。目标是每个插件一个子目录 `plugins/<id>/`，宿主只把这个目录的句柄交给插件。迁移涉及已有用户数据，需要按 V0.2 §4.2.1 的迁移规则做（先检查、原子移动、幂等、失败保留），单列为 Q9，不混进其他阶段。
- 偏好：沿用 `plugin_preferences`，键已经带插件 ID。

### 4.5 为什么只做编译期链接

1. **保持"单一 commit 可追溯"**。AGENTS.md 要求源提交、DMG 内应用、安装后应用、实际运行界面、Release 标签的 commit 全部一致。运行期加载的任何代码都在这条链之外：审计过的 commit 不再等于运行的代码。对一个"先审计再执行"的用户，这是不能让步的性质。
2. **进程内没有隔离可言**。动态库一旦加载，就拥有进程的全部权限：整个钥匙串 vault、所有会话、AI 密钥。清单里声明什么权限都拦不住它。
3. **Zig 没有稳定 ABI**。清单里是 Zig 函数指针、切片和编译期类型令牌（`plugin_services.zig` 的 `Definition.of`）；跨动态库边界既不安全也不可版本化。要做就得另外设计一套 C ABI，等于重写契约。
4. **macOS 签名**。加载非同一团队签名的动态库需要放宽库校验，这会削弱整个应用。**已核实：今天的打包没有启用 hardened runtime。**`scripts/package_macos.sh:74`、`:76`、`:78` 三处 `codesign --force --sign` 都没有 `--options runtime`，也没有 `--entitlements`；仓库里的 `.entitlements` 文件只在 `vendor/libghostty-vt/macos/` 下，与 ZeroWork 的打包无关。所以系统层面的库校验今天本来就没有开启。这条论据目前只能说明"将来开启 hardened runtime 后，运行期加载会与它冲突"，不能说明"今天的签名挡住了什么"。是否开启 hardened runtime 与插件化无关，登记为 6.4 的 X-1。
5. **UI 规则**。插件视图必须是 Yix + zenit 原生组件，而 Yix 是编译期生成的 Zig 代码；运行期加载的插件无法提供 Yix 视图。

**逐步开放的现实路径**：

| 步骤 | 内容 | 前提 |
|---|---|---|
| 现在 | T0 + T1，编译期，权限声明 + 注入 + lint | 本方案 |
| 下一步 | 第三方的**可执行**扩展走进程外：AI 工具用 MCP（V0.4 已规划，受当前附着范围约束） | V0.4 |
| 再下一步 | 把高风险解析器（RFB、网页内容已由 WebKit 进程承担）移到辅助进程，经现有的帧 / 事件通道回传 | 有性能与复杂度证据后单独立项 |
| 有需求时 | T2：外部源码审计后 vendoring，编译期链接 | 出现第一个真实候选 |
| 不做 | 进程内运行期加载（动态库、脚本引擎） | — |

最后一行是硬性规则（Q8 已判定），由 `ident:no-dylib` 机检（3.3）。它不覆盖进程外通道：V0.4 的 MCP 由应用启动子进程（`src/ai/mcp_native.c`，`build.zig:65` 编进 `core`），子进程里跑的是运行期才确定的第三方代码。规则的完整措辞是："进程内不加载任何运行期代码；第三方可执行扩展只能走进程外通道（目前只有 MCP），它的启动命令、可用工具与审批受 V0.4 的附着范围约束，并有自己的威胁模型。"MCP 子进程虽然在进程外，仍是一条新的运行期代码面，不能因为它不在进程内就当作已经隔离。


---

## 5. 迁移路线

### 5.1 总览与排序

| 阶段 | 内容 | 性质 | 与 UI 重构的关系 |
|---|---|---|---|
| PL0 | 本文评审、用户拍板 | 无代码 | 不依赖 |
| PL1 | 清单真实化：`summary`、`permissions`、能力目录与证据校验、路线条目；设置页改读清单；**`bundled` 插件的禁用机制（Q5）** | core + 设置 model；除权限文案外界面等价；禁用机制默认不改变任何行为 | **必须排在 PL2 之前**（协议插件面板已不在 P3 3e 内，见 6.2.1） |
| PL2 | 设置页按设计稿落地：列表（T5k96）、单协议页（KUKQ5）、能力对照表（ibeKI），`.yix` 实现；**单协议页上的启用开关（Q5）** | 功能改动（`feat`） | 取代 P3 3e 对该面板的像素等价改写（Q2 已判定，例外条款见 6.2.1） |
| PL3 | `plugin_api` 层、`plugins/index.zig`、内置三项各有清单、`plugins/remote` 归位、core 与 features 对插件的 import 清零、新规则上线 | 行为不变的重构 | 等于 P5 里"插件分层"那一步；跟在波次 A（connections）之后 |
| PL4 | 内容卡片：4a 卡片类型与约束（复用现有 group / split）；4b 会话记录收敛为一张卡片；4c 删除 AI 停靠模式（4c-3 同时把浮动范围扩到整个窗口）；4c′ AI 登记为卡片；4d（可选）容器路径合并 | 4a、4c′、4d 行为不变；4b、4c 是用户可见的改动 | 4a 在波次 C 之前或同时；4b 的 H1–H2 就是波次 A 里 history 的分层，H3–H5 在 4a 之后；**4c 排在 P5 的 AI 两步（波次 B 外壳 Yix 化、波次 C `AiHost` 拆分）之前**，可独立尽早做；4c′、4d 跟随波次 C |
| PL5 | 插件视图 Yix 化（bmc、fixture）；删除过渡层 | 行为不变的重构 | 等于 P5 第二步（Yix 化）在插件上的部分；P6 之前完成 |
| PL6 | V0.5 网页连接按新模型接入并删除其路线条目；可选：命令贡献、动作能力词表收敛 | 功能 | P6 之后 |

排序的三个硬约束：

1. **PL1 先于 PL2**。协议插件面板已判定不在 P3 3e 内做像素等价改写（6.2.1），它的 view-model 直接建在 PL1 的新数据源上。
2. **PL3 不早于 P2 完成、不晚于 P5 结束**。Revamp 方案把插件的过渡条目留给 P5（`tools/arch/rules.zon:7-8`），PL3 + PL5 就是那项工作的具体内容。
3. **PL4c（删除 AI 停靠）先于 P5 的 AI 波次；PL4c′（AI 登记为卡片）依赖波次 C**。前者是为了不把要删的代码先迁一遍；后者是因为在 `workspace.zig` 和 `AiHost` 拆分之前往上面加卡片宿主，会与拆分互相冲突。
4. **PL4a 内部分两段，与波次 C 的先后写死**（GLM B-12）：M1–M6（卡片注册表、`card_type` 字段、入组条件改读约束、roster 准入）只改模型与几处判断，可以在波次 C 之前做；M7（窗口级浮动层，即卡片宿主的新 host 代码）**排在波次 C 的 `Workspace` 拆分提交之后**，否则新 host 代码要跟着拆分来回 rebase。依赖 M7 的 PL4b H3–H5 与 PL4c′ 因此也都在波次 C 之后。
5. **PL4a 的 M1–M6 不依赖 PL3，可以与 PL3 并行**（GLM B-13）。唯一的耦合是 `CardViewDef` / `CardInstance` 放在哪个文件：PL3 之前先放在 `host/plugin_ui_contract.zig`（与现有 `RendererDefinition` 并列），PL3 建 `plugin_api/ui.zig` 时连同其余 UI 契约一起搬走。两者谁后合并，谁负责搬。这样 P2 / P5 的进度回退不会把 PL4a 一起拖住。GLM 也确认两者之间没有循环依赖。

每个阶段都要过 Revamp 方案 6.1 的通用门禁（`check-yix`、`check-arch`、构建、`test`、`test-ui`），下面只列各阶段额外的退出标准。

### 5.2 各阶段

**PL1 清单真实化**

内容：
1. `PluginManifest` 增加 `summary`、`host_api_minor`、`permissions`、`capabilities`；`publish` 增加 2.2 的校验 2、3、4、7。权限词表包含 `ai_integration`（4.3）。
2. 新增能力目录（core，纯数据）与求值函数；按 2.3 的准入规则逐项审计，给出定稿的目录。**AI 审计项**（第六批判定，2.5.8）：把 `supportsAssistant`（`ai_host.zig:653`）与 `ai_session_context.assemble`（`ai_session_context.zig:8`）两处读法收敛到同一个谓词函数 `assistantDeclared(manifest)`，取 `integration.ai or ai_context != null`；能力目录的"附着 AI 助手"也读它。今天所有清单的 `integration.ai` 都为真，所以收敛不改变行为（单测逐清单断言新旧结果相同）。这个函数在 PL4a 改为从卡片类型派生，PL1 不提前引入卡片上的 AI 声明。
3. 新增 `src/plugins/roadmap.zig`；删除 `config/plugin_page.zig` 的 `PlannedProtocol`、`plans`、`PreviewKind` 与校验示例字段，以及它们在设置 view-model（`view_model.zig:217-250`）、预览 runner、测试里的使用。
4. local / ssh / sftp / bmc / fixture 的清单补 `summary` 与 `permissions`。`summary` 的文字直接取自现有 `description()` 的三句话，保证界面文案不变。
5. 设置的 model 增加"插件目录快照"（纯数据：行、能力、权限文案、偏好字段、路线条目、对照矩阵、**每个 `bundled` 插件的启用状态**），由设置 host 经 Ports 从注册表与"已链接插件表"（见第 6 条）构造；删除 `settings_plugins.zig` 的 `description()` 与 `permissions()`。
6. **禁用机制（Q5，设计见 6.2.1）**：组合根导出一张不需要初始化插件就能读的"已链接插件表"（ID、显示名、`summary`、版本、`origin`、`permissions`）；启动时在构造插件 bundle（今天是 `app/main.zig:87` 的 `application_plugins.Bundle.init`）**之前**读出各插件的 `host.enabled`，被禁用的 `bundled` 插件不初始化、不交给注册表；保存的主机遇到被禁用插件时给出"已禁用"原因。PL1 不加界面开关，可以靠改配置文件验证。
7. （暂缓，Q19）`AGENTS.md` 加入 4.3 的审计 checklist。PL1 不做这一步。

退出标准：
- 单测：无证据的能力声明被拒绝；冒用目录 ID 被拒绝；敏感依赖未声明权限被拒绝；有工具或 AI 集成但未声明 `ai_integration` 被拒绝；`host.` 前缀的偏好键被拒绝；路线条目与已注册 ID 冲突被拒绝（在包含全部生产清单的测试里）；`design_doc` 不存在被拒绝。
- 单测：对当前五份清单求值的能力集合有逐项断言（这份断言就是"N 项能力"的事实来源）。
- **界面**（GLM B-11）：权限文案从按 ID 写死改为由词表生成，不可能与旧句逐字相同，所以退出标准分两部分。权限行与权限弹窗的文案等价，新旧对照表经用户认可，并且包含"声明性约束，不是授权门禁"一句（单测断言）；其余部分截图逐像素一致。`e2e/plugin_settings_v3_native.ts` 第 36、41 行截了 local 的权限弹窗（`local-permissions`、`permissions-compact`），这两张截图在同一提交里按新文案更新基线并写明理由。
- 说明文案：`summary` 逐字沿用现有三句，`plugin_settings_v3_native.ts:25-27` 对三句说明的断言不改即通过；`e2e/v02_plugins_ui.ts` 只断言行与几何，不改即通过。
- `settings_plugins.zig` 里不再有插件 ID 字面量。
- 禁用机制：见 6.2.1 Q5 的"退出标准与测试"中属于 PL1 的部分。默认配置（没有 `host.enabled` 条目）下全量 e2e 与截图不变。
- AI：`src/` 里判断"能否附着 AI"的代码只调用 `assistantDeclared`，不再直接读 `integration.ai` / `ai_context`（运行时状态门禁不在此列）。

测试与 test_id 影响：现有 `settings.plugin.<id>.*`、`settings.plugins.*` 全部不变。依赖 `PreviewKind` 的测试（`settings_content_tests.zig:1033` 附近、`plugin_page.zig` 的文件内测试、预览 runner 的 `--preview-kind` 参数）随被删的功能一起删除，测试计数基线在同一提交里更新并写明理由。权限文案的断言在单测里，不在 e2e 里（已核实）：`src/features/settings/tests/plugin_settings_v3_tests.zig:65` 断言非内置插件的权限句"连接时按需请求权限"，`:64` 断言说明回落为 `workspace_kind`；PL1 删除这两个函数时同步改写这条单测。`settings.plugin.ssh.version.message` 的断言在 `plugin_settings_v3_native.ts:33`，不是 `v02_plugins_ui.ts`（GLM B-8 指出的归属错误，已更正）；版本弹窗文案不受 PL1 影响。

**PL2 设置页按设计稿落地**

内容：`features/settings/view/panes/plugins.yix` + `.yss`，三个界面——分组列表（已内置 / 随应用提供 / 计划中 + 能力对照入口）、单协议页（身份卡、**启用开关（仅 `bundled`，zenit 原生 Switch，Q5）**、支持的能力、不支持的能力及"由 X 提供"、权限、偏好字段）、能力对照表。数据全部来自 PL1 的快照。删除该面板的 `LegacyBody` 包装（`YIX_EXCEPTIONS` 的 S-7 中属于协议插件的那一份）。

退出标准：
- 与 Pencil 节点 T5k96、KUKQ5、ibeKI 的 `design_diff` 分数达到设置窗口其他面板的同等水平；与设计稿的已知差异（能力数字、SSH 的文件能力、无 Ansible）逐条写入 `PENCIL_MAP.md` 并得到用户认可。
- 明暗主题、搜索有结果 / 无结果、带偏好字段的插件（fixture）各有截图。
- `features/settings` 在 check-arch 基线里没有条目。

测试与 test_id 影响：
- 保留并继续有效：`settings.plugins`、`settings.plugins.list`、`settings.plugins.builtin`、`settings.plugins.bundled`、`settings.plugin.<id>.row`、`.name`、`.description`、`settings.plugin.<id>.<偏好键>`。
- 语义变化：`settings.plugin.<id>.detail` 从"右侧详情窗格"变成"单协议子页"；`settings.plugin.<id>.version`、`.permissions` 及其 `.dialog` / `.close` 等弹窗部件，在新设计里版本与权限是子页内的行，弹窗是否保留取决于设计。凡是删除或改变语义的 id，在同一提交里改 `test_ids.baseline.txt` 并写明理由（Revamp 6.3 第 1 条）。
- 新增：`settings.plugins.planned`、`settings.plugins.planned.<id>`、`settings.plugin.<id>.capabilities`、`settings.plugin.<id>.capability.<能力 id>`、`settings.plugin.<id>.unsupported`、`settings.plugins.matrix`；Q5 的 `settings.plugin.<id>.enabled`、`settings.plugin.<id>.enabled.hint`、`settings.plugin.<id>.disabled`（见 6.2.1）。动态 id 由 `model/ids.zig` 生成。
- e2e：`plugin_settings_v3_native.ts` 断言了主从布局的几何（216pt 列表窗格等），需要重写为两级导航；`v02_plugins_ui.ts` 的弹窗断言按上一条处理。

**PL3 分层与 `plugin_api`**

内容：
1. 新建 `src/plugin_api/{mod,ui}.zig`，把 `host/plugin_ui_contract.zig` 的 UI 类型搬到 `ui.zig`，core 侧保留不含 `ui` 的部分。
2. 新建 `src/plugins/index.zig`；local / ssh / sftp 各自新增 `manifest.zig` 与 `mod.zig`，把 `linked_plugins.registerAll` 里 7 处 `switch` 拆回各自的清单；删除 `LegacyPluginId` 驱动的拼装、`legacy_descriptor`、`legacy_registration`，`session_host.zig` 的 6 处读取改读清单字段。
3. app 构造注册表并注入 `SessionHost`，删除 `session_host.zig:363` 的反向 import。
4. `plugins/remote/` 归位 `features/connections/wizard`。
5. bmc 按 `engine / model / host` 分层（视图暂留命令式，放在 `view/` 并进基线）；对 `src/host/*` 的 import 全部改经 `plugin_api`。
6. `features/ai` 对 bmc、ssh 内部文件的 import 改经类型化服务。
7. 1.7(c) 的按 ID 分支逐项改为读清单或服务（图标读 `manifest.icons`；侧栏路由读 `route` 服务；向导默认选择读贡献）。图标有一处不能机械替换（已核实，GLM E-(v)）：`session_icon.zig:98` 在主机系统未知时，对 ssh / sftp 回退到彩色位图 `host_os_assets.linux`（测试 `:137` 断言），而清单 `icons.tab` 里 ssh / sftp 是线条图标 `terminal` / `folder`（`linked_plugins.zig:82-83`），资源与渲染路径都不同，直接改读 `icons.tab` 会变像素。做法：`Icons` 增加一个可选字段（例如 `unknown_host_os: ?[]const u8`），ssh / sftp 填 `"linux"`，`forHost` 改读它；`:84` 对 `"bmc_ikvm"` 写死的 `screen_share` 同样改由 bmc 清单提供。退出标准里的"截图逐像素一致"覆盖这一处。
8. check-arch 新规则上线，重建基线。

退出标准：
- `layer:core->legacy_plugin`、`layer:core->plugin_registry` 在基线里为 0；core 与 features 各层到任何 `plugin_*` 层的矩阵违规（3.3 的 `no-plugin-import`，新规则名形如 `layer:host->plugin_host`）在基线里为 0。
- **硬退出项（GLM C 节）：`src/features/ai/**` 不 import `src/plugins/**`，测试代码也不例外**。今天非测试的是 `ai_host_queries.zig:10-11`（bmc 的 `console_service`、`tools`），改经类型化服务与工具绑定；测试里的（`ai_tools.zig:1280`、`:2071`、`:2109-2153`，`ai_lifecycle_controller.zig:1502`、`:1540`、`:1767`）挪到对应插件的 `tests/`。在这一项清零之前，"插件能力经类型化服务提供"只是纸面状态，文档与报告都不得这样宣称。
- 内置级插件到 core 的 import 条数（3.2）不高于规则上线时的基线。
- `plugin_api` 的 API 面快照单测（3.1）上线。
- `ident:no-plugin-id-branch` 的基线只剩允许名单内的兼容 codec。
- V0.2 §9.0 的"注册控制"门槛可以用测试证明：测试构建移除某个内置清单后，它的创建入口、服务、工具随快照消失，其他协议不受影响。
- 全量 e2e 回归；截图逐像素一致；测试用例数不减。

测试与 test_id 影响：不改任何 test_id。跨 feature 引用插件内部文件的测试（基线里 `cross-feature` 的测试条目，例如 `wizard_tests.zig` → `plugins/remote/editor.zig`）随文件归位自然消失；直接构造 `LegacyPluginId` 的测试桩（`session_host.zig:1876`、`:2326`，`application_host.zig` 文件内测试多处）改用清单。`tests_plugin_fixture.zig`、`tests_bmc.zig` 两个聚合根的 import 路径随目录调整。

**PL4 内容卡片**

4a 卡片类型与约束（行为不变）——对应 2.5.5 的 M1–M6：
- core 增加 `CardTypeDef` 与卡片注册表；`plugin_api/ui.zig` 增加 `CardViewDef`、`CardInstance`；`features/terminal`、`features/files` 登记 `terminal`、`file`，取代 `shared_renderers` 占位；现有 `RendererDefinition` 经适配层登记。
- **AI 能力移到卡片类型（M9，第六批判定，2.5.8）**：`terminal`、`file`、`bmc_ikvm` 声明 `CardTypeDef.ai`（上下文提供者分别来自今天的 `ai_local_tools` / `ai_ssh_tools`、`ai_file_tools`、bmc 清单的 `ai_context`）；`supportsAssistant`、上下文组装、`assistantToolsAvailable` 改为从 tab 里的 AI 卡片派生，运行时状态门禁按卡片保留；清单级 `integration.ai`、`ai_context`、`ai_adapter_factory` 在同一阶段的最后一个包里删除；`publish` 校验插件定义的带 `ai` 的卡片类型须有 `ai_integration` 权限。绑定对象仍是 `.session` / `.group`，统一为 tab owner 放在 4c′（M10），因为它要动 `AiHost` 的主体，必须在波次 C 拆分之后。
- AI 部分的退出标准：对现有每一种 tab 状态（单会话的本机 / SSH / SFTP / bmc / fixture、会话组、归档、关闭中、失败、断开、EOF），新旧 `supportsAssistant`、上下文是否可组装、`assistantToolsAvailable` 的结果逐项相同；AI 相关 e2e 不改即通过（上下文机制在 M11 才改，M9 不动生产请求的系统提示与工具列表）；清单里不再有 `integration.ai`、`ai_context`、`ai_adapter_factory`。
- `SessionTab` 增加 `card_type`，与现有布尔标志并存并用断言保持一致。
- `canGroupTarget`、窗格头的分屏条件、拖出成独立 tab 的路径改为读卡片类型的约束；roster 的成员准入显式限定为会话卡片。
- `group_layout` 的数据结构与快照格式不动。
- **前置包（Q16 已判定）**：在 PL4a 开始之前，单独一个包删除 `features/workspace/model/pane_manager.zig`、`features/shell/model/shortcut_dispatch.zig`、`features/workspace/model/group_dispatch.zig` 及其测试，以及 `src/root.zig` 里对应的导出与 `_ =` 引用（`:94`、`:99`、`:101`、`:282`、`:286`、`:288`）。删除前逐条核对这些测试覆盖的行为（例如快捷键分派的规则）在运行期实现里是否已有测试；没有的就把用例改挂到运行期实现上，不能随文件一起丢掉。退出标准：构建与 `test` 通过；测试计数的减少在提交说明里逐条写明去向（删除或改挂）；check-arch 基线只减不增。
- 分两段：M1–M6 可在波次 C 之前、可与 PL3 并行；M7 在波次 C 的 `Workspace` 拆分之后（5.1 的硬约束 4、5）。
- 退出标准：全量 e2e 与截图不变；现有分组 / 分屏 / 拖拽入组 / 布局恢复的测试不改即通过；新增等价性单测——对现有每一种 tab 状态，新旧入组条件的结果相同，窗口移交的判定（`workspace.zig:5157`、`:5192`）新旧结果相同；`CardId` 同槽位不同代次判为不等；vtable 的 `mount` / `unmount` 配对被断言保护；`publish` 不再要求 `workspace_kind == content_renderer`（改为校验 `cards`）；一个无会话工厂、只登记一个 `standalone_tab = true` 卡片类型的测试清单能注册成功并打开 tab；约束被拒绝的放置（例如把 `split = false` 的卡片拖进分屏）有单测。
- test_id：`workspace.plugin.content` 及分组、窗格头的现有 id 全部保留。

4b 会话记录收敛为一张卡片（**用户可见的行为变更**，`feat(history)`）：

*现状*（要收敛的四块）
- 记录目录：`HistoryHost`（`src/features/history/host/history_host.zig`，747 行）。全窗口模态层（`:66-70`，`z_index = 500`、焦点陷阱）里放一张宽 300 的目录卡片（`:271` 起）；状态是筛选（全部 / 本地 / SSH）、搜索、翻页、删除确认、清理。
- 打开一条记录：点 `history.record.view` → 若已打开则 `workspace.focusArchive`，否则启动加载作业 `loading.Job`（`:436-442`），完成后 `workspace.openArchiveDocument`（`:603`），目录层随即关闭。
- 归档 tab：`Workspace.openArchivedContent`（`workspace.zig:5630` 起）新建 `content_owner = .history`、`archived = true` 的 `SessionTab`，内容是一个处于历史模式的终端视图。
- 回放与阅读：模型在 `features/history/model/{history_replay,history_reading,history_archive,history_cast}.zig`，但由 `features/terminal/view/terminal_view.zig` 和 `workspace.zig` 直接消费；回放条的 test_id 是 `terminal.history.{card,notice,position,title,track}`。

*目标结构*

```
features/history/
  model/
    card_vm.zig        卡片根 view-model：持有 list、detail；当前选中的记录；布局模式
    list_vm.zig        目录：筛选、搜索、翻页、删除确认、清理；来自 HistoryHost 的状态
    detail_vm.zig      详情：加载状态、时间线位置、阅读模型；来自 history_replay / history_reading
    ports.zig          目录读取、打开记录（加载作业）、删除、导出、清理
    ids.zig
    history_list.zig  history_archive.zig  history_replay.zig  history_reading.zig  history_cast.zig（现有，位置不变）
  view/
    history_card.yix   列表栏 + 详情区
    list.yix  detail.yix  styles.yss
  host/
    history_host.zig   实现 Ports；把卡片登记为 `history` 类型
```

view-model 的划分：

| view-model | 状态 | Intent（举例） | 说明 |
|---|---|---|---|
| `CardVm` | `selected: ?RecordKey`；`layout: { split, list_only, detail_only }`；来源筛选的初值 | `select(key)`、`back_to_list`、`open_as_tab`、`close` | 唯一协调者：`list` 发出"选中"，`CardVm` 让 `detail` 加载。卡片宽度不足以并排时退化为列表 / 详情二选一并带返回 |
| `ListVm` | 记录切片（拥有型、带稳定 id）、`filter`、`query`、页码、删除确认、消息 | `set_filter`、`set_query`、`next` / `previous`、`delete` / `confirm_delete`、`export`、`clear`、`retry` | 不知道详情的存在；不直接打开任何东西 |
| `DetailVm` | `phase: { empty, loading, ready, failed }`、记录标题与元信息、时间线位置、阅读模型 | `seek`、`retry`、回放条上的现有操作 | 不知道列表的存在。加载作业的代次校验沿用 `HistoryHost.generation` 的做法：过期结果丢弃 |

- 详情区的终端回放画面本质上是终端表面，由 `features/terminal` 经门面 `mod.zig` 导出一个"只读回放表面"组件，`history` 的视图嵌入它（跨 feature 只经门面）。它属于 `YIX_EXCEPTIONS` 里终端表面那一类 (b) 例外，不新增例外种类。
- 一张卡片一个 `CardVm`，因此每张卡片有各自的选中记录；所以"tab 可以开多张"（Q15）不需要额外机制。"浮动最多一张"按 tab 归属理解（2.5.7）：由卡片宿主在打开时校验，当前 tab 已有浮动的 `history` 卡片时，再次从入口打开只是把它带到前台；当前 tab 没有时新建一张，归属当前 tab。卡片类型的声明相应是"tab 不限、每个所属 tab 最多一张浮动"（`float_per_tab = 1`）。
- 浮动时遵守 2.5.7：可停放在整个浮动区域；切换到别的 tab 时收回到所属 tab，切回时展开回原位；位置以窗口内容坐标记录。

*迁移步骤*

| 步 | 内容 | 行为 |
|---|---|---|
| H1 | `HistoryHost` 分层：抽出 `ListVm` 与 Ports，旧的命令式视图改为只和 `ListVm` 打交道。这就是 P5 波次 A 里 history 的"分层"那一步 | 不变 |
| H2 | 抽出 `DetailVm`：把 `openArchiveDocument` / `openArchivedContent` 里构造时间线与阅读模型的逻辑从 `workspace.zig` 移进 `features/history`；`features/terminal` 的门面导出只读回放表面。归档 tab 暂时改为"一个只含详情的宿主"，外观不变。**退出标准增加**（GLM C.c）：`features/terminal/mod.zig` 导出的回放表面接口冻结——签名写进一个契约单测（构造、挂载、seek、卸载），此后改动它必须同时改这条单测并在提交说明里写明，terminal 自己的分层步骤不得顺手改它 | 不变 |
| H3 | 新建 `history_card.yix`（列表栏 + 详情区）与 `CardVm`；登记 `history` 卡片类型（依赖 PL4a 的注册表与窗口级浮动层） | 新卡片存在但未接入入口 |
| H4 | 切换入口：标题栏"回看日志"（`features/shell/host/chrome_mount.zig:23-24`）与资产右键菜单（`menu_host.zig:687-688`，带来源筛选）改为打开浮动的 `history` 卡片；`history.record.view` 改为在卡片内选中，不再新开 tab；卡片头增加"作为 tab 打开" | **变更** |
| H5 | 删除旧路径：全窗口模态层；`Workspace` 的 `openArchiveDocument`、`openArchivedContent`、`focusArchive`（`workspace.zig:5563-5671`）；`SessionTab.archived` 及其全部分支（图标、状态文本、`canGroupTarget`、AI 的 `supportsAssistant` 等）；`ContentOwner.history` 与 `HistoryId`（`identity.zig:85`），改为普通的 `card` owner | 清理 |
| H6 | 更新 `PENCIL_MAP.md:90`：删掉"目录是模态、不能和回放同时常驻"这条保留差异，把"停靠在 view island 左侧"改写为卡片内部的列表栏 | 文档 |

H1、H2 可以在 PL4a 之前做（它们就是 P5 的 history 分层）；H3–H5 在 PL4a 之后。

*旧持久化数据*
- **没有找到"已打开的归档 / 回放 tab"的持久化**：`src/config` 与 `features/workspace/model` 里没有保存归档键或已打开 tab 列表的代码，全仓也没有找到恢复 tab 的入口；归档 tab 只存在于本次运行的内存里。所以没有需要迁移的"已打开 tab"数据。
- 唯一持久化的工作区布局是组的分屏快照（`group_layout.Snapshot`），而归档 tab 从来进不了组（`canGroupTarget` 要求 `!archived`），快照里不会有它。
- 磁盘上的记录本身（归档清单、cast、检查点）不动，卡片读的是同一份数据。
- 上面两条"没有找到"是 grep 的结论，执行 H5 之前再核对一次；如果发现有持久化，规则是：读到旧的归档 tab 条目时改为打开一张 `history` 卡片并选中该记录，读不到对应记录就丢弃该条目，不报错。

*e2e 与 test_id*
- `history.*` 现有 36 个基线 id，其中 21 个被 e2e 使用。全部保留，落在同一语义节点上：`history.panel` 是卡片根（浮动时是浮动卡片，tab 时是卡片内容根）；`history.search`、`history.query`、`history.filter.*`、`history.count`、`history.viewport`、`history.record*`、`history.previous` / `next`、`history.clear`、`history.delete.*`、`history.confirmation`、`history.empty*`、`history.message`、`history.retry` 都在列表栏里，语义不变。
- 语义变化的两个：`history.record.view` 从"新开归档 tab 并关闭目录"变成"在卡片内选中并显示详情"；`history.close` 从"关闭模态层"变成"关闭这张卡片"。两者 id 不改名，变化写进提交说明。
- `terminal.history.{card,notice,position,title,track}`（回放条）保留原 id，节点移到卡片的详情区里。前缀仍是 `terminal`，按 Revamp 的 D12（本工作流内不改名）只登记不改。
- 新增：`history.list`、`history.detail`、`history.detail.empty`、`history.detail.loading`、`history.back`、`history.open_as_tab`，由 `model/ids.zig` 给出。
- 受影响的 e2e：
  - 必改：`history_log_native.ts`、`global_history_native.ts`（及配套的 `global_history_theme_pixels.py`）、`patch_history_native.ts`。凡是"点查看之后断言出现新 tab / 目录层消失 / 页签图标变成历史"的步骤，改为断言卡片内详情出现；目录的 `rect` 断言随卡片几何更新。
  - 需要逐个核对的候选（脚本里出现了 `history.panel`、`history.record*` 或 `terminal.history.*`）：`ai_terminal_history_close_native.ts`、`builtin_records_native.ts`、`builtin_records_dispatch_native.ts`、`builtin_records_ssh_native.ts`、`workspace.ts`、`mist_workspace_native.ts`、`floating_input_native.ts`、`vanta_error_states_native.ts`、`visual_audit_capture.ts`、`command_annotations_native.ts`、`command_annotations_ai_native.ts`、`builtin_clear_native.ts`，以及 `notification_*` 中的几个。其中只涉及实时终端"只读历史页"的脚本不应受影响（Q14 已判定不并入）。
  - Zig 侧：`features/terminal/tests/{builtin_records_tests,terminal_surface_view_tests}.zig` 直接引用历史模型，随 H2 调整 import；依赖 `tab.archived` 的 workspace 测试随 H5 改写。
  - 浮动相关（2.5.7）：新增 `e2e/float_card_tabs_native.ts`，覆盖 `history` 与 AI 两种浮动卡片：拖过原内容区边界后的位置、禁区夹取、切走后隐藏、切回后矩形与之前相同、窗口缩小 / 放大后的夹取与恢复、"每个 tab 最多一张浮动 `history`"。动效断言（zenit 同步进 vendor 之后）：`anchor` 模式下切走时卡片进入收回状态（`AnchorTransition.phase()`），结束时的矩形等于所属 tab 节点的矩形（`currentFrame()`），切回时从该矩形展开到原位置；`fade` 模式下矩形中心不变、尺寸按 Z12b 的 token 缩小并淡出（Z12b 落地前只断言淡出）；开启"减少动态效果"时两种模式都只淡入淡出；切换设置后下一次切 tab 即按新模式执行；快速来回切换时中途改向、不排队。卡片根节点上暴露的收回状态即 `phase()` 的四个值。
  - 新增 test_id：`float.layer`（窗口级浮动层的根）；卡片的收回状态（`shown` / `collapsing` / `collapsed` / `expanding`）以可断言的方式暴露在卡片根节点上（`history.panel`、`ai.panel`），具体形式由执行者按 e2e 工具能读到的属性定，不为状态单独造节点。

*退出标准*
- 浮动与独立 tab 两种放置各有截图（明暗主题）；在两种放置之间移动后，筛选、搜索词、滚动位置、选中的记录与回放位置保持。
- 列表与详情同时可见；窄卡片下退化为二选一且可返回。
- 把会话记录卡片拖进分屏被拒绝并有提示（`split = false`）。
- 可以同时打开多张 `history` tab，各自的选中记录互不影响；当前 tab 已有浮动卡片时再次从入口打开，只把它带到前台，同一 tab 不出现第二张浮动卡片；在另一个 tab 打开时为那个 tab 新建一张，两张各自归属、互不影响（Q15 按 tab 归属，2.5.7）。
- 设置 › 外观与主题 › 终端与工作区有"浮动卡片切换动画"单选（`settings.field.float_card_transition`），默认"收向所属标签"；改为"淡出"后立即生效；配置键按常规写出（依赖 config-unknown-keys，已合入），有单测。
- 浮动卡片可以拖过原 tab content 的边界停放到浮动区域的任意位置，不能进入标题栏和展开时的侧栏，可以覆盖状态栏（Q20）；切到别的 tab 时隐藏，切回时回到原位置；窗口缩小后被夹回可见区域，放大后回到原位置。切换 tab 时按设置项 `ui.float_card_transition` 退场与入场（默认收向所属 tab），"减少动态效果"开启时只淡入淡出；动效断言见下面的 e2e。
- `src/` 里没有 `archived` 的 `SessionTab` 分支、没有 `ContentOwner.history`；`features/history` 在 check-arch 基线里没有条目。
- 上面列出的 e2e 全部通过，改动逐条有记录；CC3v4 的 `design_diff` 不低于改动前。

4c 删除 AI 停靠模式、AI 条、悬停预览与"钉住"，AI 只浮动（**用户可见的行为变更**，`feat(ai)`，不是行为不变的重构）。建议拆成三个包，各自可回滚：4c-1 删除停靠布局；4c-2 删除 AI 条、悬停预览、钉住并收敛显隐状态，删除标题栏的 `toolbar.ai`，以每个 tab 的浮动 AI 图标 `ai.launcher` 作为入口（第七批判定；设计稿已定稿，XqqLV）；**4c-3 浮动范围扩到整个窗口（2.5.7）**。三个包都排在 P5 的 AI 波次之前。4c-3 不依赖 PL4a 的浮动层：它只改 `float_model` 的边界来源与最大化语义；收回 / 展开动效要等 Z12，并随 4c′（AI 改由浮动层承载）接入。

*4c-3 浮动范围扩到整个窗口*
- **已完成（ai-panel-anchor）**：浮动范围、最大化语义、默认位置（就近展开）、#52 尺寸与 Z12 出入场都由通用卡片浮动层实现（2.5.7"实现：浮动由通用卡片浮动层实现"）。下面原计划里"只改 `float_model` / `ai_float_gestures`"的做法被用户判定取代：`ai_float_gestures.zig` 已删除，`float_model.zig` 只剩 AI 卡片类型的声明与 AI 状态；"切换 tab 时仍直接隐藏 / 显示"一条也已提前做成 Z12 收回 / 展开。
- `src/ai/float_model.zig`：`safeBounds(pane, window)` 改为只接收 shell 给出的浮动区域（2.5.7 的"禁区"之外），`clampRect`、`resized`、`Model.rect`、`toggleMaximized` 随之改为以浮动区域为界；`pane` 只在计算首次打开的默认矩形时作为锚点参考（锚点见下面的"默认位置"），不再参与夹取。
- `src/features/ai/pane/view/ai_float_gestures.zig`：`updateBounds` 改为接收浮动区域与所属内容区两个矩形，语义分开（前者夹取，后者只做默认锚点）。
- `src/features/shell/host/nav_host.zig:585-591`：今天传的是 `ownerBounds()` 与整个视口，改为传 shell 计算的浮动区域（视口 − 标题栏 − 展开时的侧栏 − 四周 8pt；包含状态栏，Q20）与 `ownerBounds()`。
- 记录方式不变：`desired` 与 `clamped` 分离，坐标是窗口内容坐标（2.5.7）。每个归属对象各存一份，切换 tab 时的存取（`ai_host.zig:732-768`）不变。
- 切换 tab 时：4c-3 只改范围，仍直接隐藏 / 显示（与今天相同）；出入场动效在 4c′ 接入（Z12 第一级已在上游完成，待同步 vendor；按设置项 `ui.float_card_transition`）。
- 单测：`float_model` 的测试 "AI default float centers below its own pane strip and clamps within the pane"（`float_model.zig` 文件内，PL4c-2 已因 AI 条删除而改写）改为"默认矩形以所属内容区为锚点、在浮动区域内夹取"；新增"拖过所属内容区边界后不被拉回""最大化铺满浮动区域""区域缩小后夹取、放大后回到 `desired`""禁区不可进入"。

*删除的代码*
- `src/features/ai/pane/view/ai_pane_layout.zig`：`State.docked`、停靠几何（`rect`、`reserve`、`clampedWidth`、`default_width = 500`、`min_session_width`）、分隔条拖动（`beginResize` 等）、`apply`（`:56`）与 `keepDocked`（`:103`）的停靠分支、`chromeHeight(docked)`（`:112`）的停靠取值。只服务浮动的部分并入浮动视图后，整个文件删除。
- `src/features/ai/host/ai_host.zig`：字段 `pane`（`:66`）、`toggleDocked`（`:3784` 起）及其图标与无障碍文案切换、分隔条拖动处理（`:3800` 起）、`dock_titlebar`（`:63`）中仅为停靠服务的部分；`:2973` 的 `and !self.pane.docked` 条件去掉。
- `src/features/shell/host/nav_host.zig:589-637`：`docked` 的计算、`pane_layout.apply` / `keepDocked` / `chromeHeight(docked)` 的调用，以及给 island 预留右侧宽度的 `ai.pane.reserve(...)` 与对应的 `inset`。会话窗格不再为 AI 让出一列。
- `src/app/main_window.zig`：停靠切换按钮 `ai_dock`（`:144`，test_id `ai.dock`）与分隔条 `ai_split`（`:258-260`，test_id `ai.pane.resize`）。`ai_panel` 容器本身（`:94-103`）保留，它就是浮动层里的 AI 卡片。
- `src/features/ai/pane/view/ai_float_gestures.zig`：`docked` 字段与 `setDocked`（`:25`、`:74-76`），以及 `:95`、`:107` 两处 `!self.docked` 条件。
- `src/features/ai/pane/tests/ai_panel_visibility_tests.zig:92` 起的停靠几何测试。
- AI 条：`src/features/ai/cards/view/ai_strip_view.zig`、`ai_strip_styles.zig` 整个文件；`features/ai/mod.zig` 里的 `ai_strip_view` 导出；`src/app/main_window.zig:557-560` 的挂载；`AiHost` 的 `strip` 字段（`ai_host.zig:60`）、`openFromStrip`、AI 条的状态刷新（`:3005-3036`）。引用 AI 条的还有 `features/shell/view/background_layers.zig`、`features/shell/tests/{material_performance,material_popup}_tests.zig`、`features/ai/cards/preview/ai_recovery_preview_runner.zig`、`features/ai/cards/tests/ai_tool_results_view_tests.zig`，逐个清理。
- 悬停预览：`AiHost` 里按鼠标位置计算 AI 条 / 面板悬停并驱动状态机的整段（`ai_host.zig:2957-2982`），以及 `toggle` 里对 `.preview` 的特判（`:3046-3047`）。
- 显隐状态机收敛：`src/ai/dock_state.zig` 的 `Mode { hidden, preview, pinned }` 收敛为只有可见 / 隐藏两态；删除 `hover()`、进入 / 离开延时（`enter_delay_ms`、`leave_delay_ms`）、`hover_blocked`、`enter_at`、`leave_at`、`pin()`。面板的打开与关闭仍然需要一个状态，但 `AiController` 的模型里已经有 `visible`（`ai_host.zig:769` 今天就在把两者对齐），所以优先方案是直接以它为唯一事实来源、删掉 `State`；`pin()` 的 8 处调用（`ai_host.zig:1507`、`:2957`、`:3047`、`:3391`、`:3577`、`:3683`、`:4982`，`nav_host.zig:2136`）改为"置为可见"。`:736` 的"切换绑定对象后仅在钉住时保持可见"改为"保持可见"——这是一处语义选择：以前悬停预览出来的面板在切换对象时会收起，现在没有预览，面板只要是打开的就保持打开。
- 文件改名：`dock_state.zig` 里剩下的只有淡入淡出的 `Reveal`（`:50` 起），文件改名为不带 dock 的名字（例如 `src/ai/panel_reveal.zig`），`AiHost` 的字段 `dock` 随之消失。改名单独一个纯重命名提交。
- **保留**：`src/ai/float_model.zig`、`ai_float_gestures.zig` 中与停靠无关的部分、`ai.panel` 容器。

*打开入口*（第七批判定，6.2.1；取代原先"以 `toolbar.ai` 为主入口"的设定）
- **删除标题栏的 `toolbar.ai` 按钮**（`chrome_mount.zig:106-111` 的 `titleIcon("✨", …)` 与其挂载）。AI 不是全局入口。
- **主入口是每个 tab 自己的浮动 AI 图标**（test_id `ai.launcher`），浮在 tab body 里，设计见 2.5.8 的"入口"。它只在 tab 能启动 AI 时出现；该 tab 的 AI 面板打开时隐藏，面板收起后重新出现。
- 其余入口保留，都作用于**当前 tab**：快捷键动作 `toggle_ai`、应用指令 `@ai`、右键菜单"问 AI"。三者今天都走 `AiHost.toggle`（`ai_host.zig:3039`）；动作规则已经是 `.scope = .tab`、要求 `.ai` 能力（`actions.zig:144`），当前 tab 不能启动 AI 时按现有规则显示不可用原因。
- 待补查：`toggle_ai` 的默认按键、macOS 菜单栏是否有对应项；缺就补一个指向同一动作的菜单项。
- AI 条原来承担的"面板隐藏时显示 AI 状态"改由 `ai.launcher` 承载（见 2.5.8 的"入口"）。
- **设计稿已定稿**（XqqLV：tfmv1 / cVXd5 / Db7OS / wqZ1s / XZGS9，规则摘要见 2.5.8 的"入口"），4c-2 可以开工；4c-1、4c-3 不受影响。

*默认位置与尺寸*
- 尺寸沿用现有浮动模式：`float_model` 的最小尺寸 520×354（**#52 已改**：默认宽 = clamp(内容宽×0.42, 320, 420)、高 = clamp(内容高−24, 280, 640)，最小 320×354）。最大化与还原在 4c-3 之后改为铺满整个浮动区域（2.5.7），4c-1、4c-2 期间不变。
- 停放范围：4c-3 之后是整个浮动区域，不再限制在所属内容区（2.5.7）。下面说的"所属窗格"只用来决定首次打开时的默认位置。
- 位置需要一个新锚点：今天的默认位置是"所属窗格的 AI 条下方居中，限制在窗格范围内"（`float_model.zig:178` 的测试名），AI 条删除后这个锚点不存在。方案是保持同一个矩形算法，把锚点换成所属窗格的上边缘（即 AI 条原来所在的位置），这样默认矩形与今天相差不超过 AI 条的高度，`e2e/ai_float_geometry_native.ts` 里对 `ai.panel` 的边界与夹取断言可以继续成立。确切数值由执行者按 `float_model` 的输入核定并写进该包的报告。
- 需要执行者核对：今天从停靠切到浮动时，浮动卡片的初始尺寸是否借用了停靠宽度；如果是，改为 `float_model` 的默认矩形。

*用户配置迁移*
- 没有需要迁移的配置：在 `src/config`、`src/features/settings`、`src/ai` 里没有找到任何持久化的停靠开关或停靠宽度；`AiHost.pane` 每次启动都以默认值初始化（`ai_host.zig:66`），停靠与否、分栏宽度都只在内存里。
- 浮动卡片的位置与尺寸是否持久化本轮没有查到；如果有，保持不变。执行前再 grep 一次，结论写进该包的报告。

*e2e 与 test_id*
- 删除的 test_id 共 7 个：`ai.dock`、`ai.pane.resize`（在 `test_ids.baseline.txt` 里，未被 e2e 使用）；`ai.strip`、`ai.strip.lip`、`ai.strip.dot.0`、`ai.strip.dot.1`、`ai.strip.dot.2`（在基线里，且都在 `test_ids.e2e_used.txt` 里）。同一提交里更新两份清单并写明理由。
- 保留且语义不变：`ai.panel`、`ai.float.drag`、`ai.float.resize.*`。（`ai.panel` 的几何约束随 4c-3 从"所属内容区内"变为"浮动区域内"，id 不变。）
- **删除 `toolbar.ai`**（在 `tools/arch/test_ids.baseline.txt:1774` 与 `test_ids.e2e_used.txt:1148`）；**新增 `ai.launcher`**（每个 tab 的浮动 AI 图标）与它的状态（`ai.launcher.state`，或在 `ai.launcher` 节点上暴露状态，以执行时 e2e 能读到的方式为准）。同一提交更新两份清单并写明理由。
- **`e2e/ai_float_geometry_native.ts` 随 4c-3 必改**：今天它向四个方向各拖 900 / 600pt（第 20 行），只断言菜单留在窗口内（`x ≥ 8`、`x + w ≤ 1432` 等）；4c-3 之后要补上卡片本身的断言——向左拖到底时卡片左边等于侧栏右缘 + 8（侧栏收起时等于 8），向上拖到底时上边等于 44 + 8，向下拖到底时下边等于窗口底边 − 8，即压住了状态栏（Q20，与状态栏节点的矩形比较），并且越过了所属终端窗格的边界（与 `terminal.surface` 的矩形比较）；最大化后的矩形等于浮动区域。第 18 行打开面板的 `ai.strip` 按 4c-2 改为 `ai.launcher`；初始 600×456 的断言不变。
- 其他可能断言"AI 在所属窗格内"的脚本：`kvm_ai_layout_native.ts`、`floating_input_native.ts`、`ai_tab_presentation_native.ts`，执行 4c-3 时逐个核对。
- **要改入口的 e2e 共 124 个**：用 `ai.strip` 的 34 个（`grep -l 'ai\.strip' e2e/*`）加用 `toolbar.ai` 的 94 个（`grep -l 'toolbar\.ai' e2e/*`，共 137 处引用），两者重叠 4 个（`ai_entry_disconnected_native.ts`、`ai_sessions_popover_native.ts`、`ai_terminal_history_close_native.ts`、`theme_material_native.ts`）。打开面板的步骤一律改为点击当前 tab 的 `ai.launcher`；**注意 `ai.launcher` 在面板打开时是隐藏的**，所以"再点一次入口关闭面板"的步骤（例如 `ai_welcome_close_native.ts` 连点三次 `toolbar.ai`）要改为点面板自己的收起 / 关闭控件（如 `ai.collapse`）或用 `toggle_ai` 快捷键。断言 AI 条本身（存在、几何、状态点、悬停预览）的步骤删除，或改为断言 `ai.launcher` 的状态。依赖 `ai.strip` 的 34 个如下：
  - AI 功能：`ai_compact_approval_native.ts`、`ai_dock_sessions_native.ts`、`ai_effort_inheritance_native.ts`、`ai_entry_disconnected_native.ts`、`ai_float_geometry_native.ts`、`ai_fork_retention_native.ts`、`ai_history_performance_native.ts`、`ai_local_picker_native.ts`、`ai_model_refresh_native.ts`、`ai_sessions_popover_native.ts`、`ai_settings_refresh_native.ts`、`ai_stream_performance_native.ts`、`ai_terminal_history_close_native.ts`、`ai_v3_native.ts`、`ai_v3_states_native.ts`、`ai_v3_unconfigured_native.ts`、`ai_welcome_native.ts`
  - 外观与图层：`button_constraints_native.ts`、`compact_popovers_native.ts`、`input_controls_native.ts`、`layer_hierarchy_native.ts`、`native_surfaces_theme_native.ts`、`layer_regressions_native.ts`、`settings_material_regressions_native.ts`、`theme_material_native.ts`、`vanta_components_native.ts`、`vanta_typography_native.ts`
  - 其他：`app_update_feedback_native.ts`、`issues_20261027_native.ts`、`mist_workspace_native.ts`、`sftp_directory_recovery_native.ts`、`sftp_v3_native.ts`、`ssh_output_performance_native.ts`、`workspace_v3_semantics_native.ts`
  - 依赖 `toolbar.ai` 的 94 个脚本清单由执行者用上面的 grep 生成并写进 4c-2 的报告，逐个记录改了哪一步。`ai_dock_sessions_native.ts` 的文件名带 dock，内容是否整体依赖停靠或 AI 条由执行者判断，必要时改名或删除。
  - 需要核对的一类：今天是否有在**没有会话 tab**（空工作区）时也能用 `toolbar.ai` 打开 AI 的脚本或功能路径（例如欢迎页）。新规则下空工作区与不能启动 AI 的 tab 都没有入口；如果确有这样的路径，记录为行为变更并在 4c-2 的报告里列出。
- Zig 侧测试：`material_performance_tests.zig`、`material_popup_tests.zig`、`ai_tool_results_view_tests.zig`、`ai_panel_visibility_tests.zig` 中涉及 AI 条、悬停预览、钉住的用例删除或改写；测试计数基线在同一提交里更新并写明理由。
- 受影响的 e2e 分两类。一类断言了默认（停靠）布局的几何，要改为浮动几何或删掉相应断言：候选是 `kvm_ai_layout_native.ts`、`ai_tab_presentation_native.ts`、`workspace_v3_semantics_native.ts`、`floating_input_native.ts`，以及所有在 AI 面板可见时截图或读取会话窗格 `rect`、终端列数的脚本（面板不再挤占会话窗格）。另一类本来就测浮动（`ai_float_geometry_native.ts`），应当不改即通过；它今天如何在默认停靠下进入浮动形态，本轮没有读透，执行者先确认。确切清单由执行者在删除后跑全量 AI e2e 得出，逐个脚本记录"改了哪条断言、为什么"。
- 截图基线：P0 保存的"迁移前"AI 截图都是停靠形态。本步骤合并后，AI 相关的截图基线和 kuRaJ 的 `design_diff` 基线要重新采集，并在 `docs/ui-revamp/baselines/` 里注明原因是产品行为变更，不是重构回归。

*与 P5 AI 波次的先后*
- **排在 P5 中 AI 的两步之前**：波次 B 的"AI 面板外壳 Yix 化"和波次 C 的"`AiHost` 拆分"。先删再迁，避免把即将删除的停靠布局、分隔条、切换按钮先分层、先写成 Yix 再扔掉。`ARCHITECTURE_PLAN.md:722` 计划把 `AiHost` 按"回合、附件、审批、停靠、会话列表、关闭确认"拆分，其中"停靠"一块随之取消。
- 它不依赖 PL4a / PL4b：只动 AI 自己的代码和 `nav_host` 的一段布局，可以作为独立的包尽早做。
- 因为它改变截图基线，要和进行中的 AI 重构包错开：合并时不能有以旧截图为退出标准、尚未合并的 AI 包。

*退出标准*
- 通用门禁全绿；`src/` 里没有 `docked`、`toggleDocked`、`ai_pane_layout` 的引用（4c-1）。
- AI 面板打开后，会话窗格的 `rect` 与面板关闭时相同。
- 浮动的移动、8 向缩放、最大化与还原与今天的浮动模式一致（4c-1、4c-2）；面板只有打开和关闭两态，没有悬停预览。
- 4c-3：AI 卡片能拖过所属内容区的边界停放到浮动区域任意位置，不能进入标题栏和展开时的侧栏，可以覆盖状态栏（Q20）；最大化铺满浮动区域；切走再切回后矩形不变；窗口缩小后夹回、放大后恢复。
- `src/` 里没有 `ai_strip`、`dock_state`、`.preview` / `.pinned` 显隐模式的引用，也没有 `toolbar.ai`；标题栏上没有 AI 按钮。
- `ai.launcher`、快捷键、`@ai`、右键菜单四个入口各有一条 e2e 或单测证明能打开当前 tab 的面板；快捷键能关闭面板。
- `ai.launcher` 只在 tab 能启动 AI 时出现（用 PL1 起的统一谓词判断，PL4a 之后自动改为从卡片派生）：本机 / SSH / SFTP / bmc 的 tab 有，不能启动 AI 的 tab 与空工作区没有；面板打开时隐藏、收起后重新出现；两个 tab 的图标与面板各自独立（tab A 面板打开时，切到 tab B 看到的是 B 的图标）。
- 面板隐藏时，待审批 / 运行中 / 失败 / 待核实 / 有新回答五种状态能从 `ai.launcher` 上看出来，并有断言。
- 图标符合定稿：48 圆形、图标 24；默认右下角右 24、下 20；KVM 帧率浮层存在时停在其上方 12；只能在 tab 内容区拖动、松手吸附四角、所有 tab 共用位置；五种状态的着色、角点与待审批脉冲（2 次、每 60s 重复）各有断言，"减少动态效果"开启时无脉冲与呼吸。与 tfmv1 / cVXd5 / Db7OS / wqZ1s 的 `design_diff` 有记录。
- 新增 test_id：`ai.launcher` 的状态（见下面的 test_id 一节）；拖动吸附用现有的 `ai.launcher` 节点断言矩形，不另设 id。
- 上面列出的 e2e 全部通过，改动逐条有记录；`PENCIL_MAP.md` 已更新。

4c′ AI 登记为卡片类型并统一绑定到 tab（行为不变；在 4a 与 4c 都完成之后，且在波次 C 的 `AiHost` 拆分之后）：
- `features/ai` 登记 `ai.chat`（只允许浮动，`binding = .tab`，自身不声明 `ai`）；AI 卡片改由卡片宿主的窗口级浮动层承载，与会话记录卡片共用同一个浮动层。
- **统一绑定（M10，2.5.8）**：`tool_scope.Owner` 增加 `.tab: TabId`，`attach` 只接受 `.tab`；单会话 tab 与组 tab 都绑定自己的 TabId；`.session` / `.group` 只在回放旧日志行时出现；`handoff` 泛化为"tab 并入容器 tab"，冲突规则不变；工具调用必须显式指定目标卡片。M10 不改变生产请求的系统提示与工具列表；上下文机制的改动在 M11（见下）。
- **拉取式 tab 上下文（M11，Q24，2.5.8）**：单独一个包，紧跟 M10，依赖 2.9 的 T1、T2（统一注册表与流水线已就位）。新增 `host.tab_context`，按 `ToolDef` 写：`target = tab`、`approval = read_only`、参数只有 `card_refs` 与 `max_bytes`、schema 固定；`terminal`、`file`、`bmc_ikvm`、fixture 各实现摘要函数，并在 `CardAi.tools` 里引用自己的细节工具；`requestSummary` 的 `<host_session_facts>` 泛化为 tab 清单（只含卡片引用、类型、身份、可用状态、可用工具名，最多 8 项）；`session_prompt.zig` 加调用引导；`ai_session_context.zig` 与 `ai_group_context.zig` 删除。
  - 退出标准：`host.tab_context` 返回结构的 golden（单卡本机 / SSH / SFTP / bmc / fixture、多卡组 tab、断开 / EOF 卡片、浮动的 AI 卡片、超预算截断、脱敏开启）；各卡片类型摘要函数的单测与 golden（bmc 不含像素）；预算取较小值与多卡分配的单测；`card_refs` 越界返回可操作错误、未知参数被拒绝；注册时 `CardAi.tools` 引用不存在的工具被拒绝；tab 清单 golden；新增一条 e2e：模拟模型调用 `host.tab_context`，断言返回条目与当前 tab 一致；断言请求 `tools` 数组或系统提示片段的现有 AI e2e 逐个核对并记录改动。细节工具沿用现有测试。
- 会话日志：新行写 `schema = 4`；旧行不改写；重启后所有对话本来就恢复为历史对话（`attached_service.zig:80-88`），所以没有需要迁移的活跃绑定。
- 退出标准（AI 统一绑定部分）：
  - M10 部分：生产请求的系统提示与工具列表与 4c′ 之前逐字相同（golden 测试）；推送式文本的 golden 测试不再需要（Q24 消解，见 M11）。
  - 单测：含 schema 1–3 旧行（`.session`、`.group` owner）的日志样本能完整回放，会话列表的来源显示不变；新绑定写出的行是 schema 4 且 owner 为 `.tab`；用 `.session` / `.group` 调 `attach` 被拒绝。
  - 单测：单会话 tab 拖入组 tab 时对话交接给组 tab；组 tab 已有附着对话时按 `BindingConflict` 处理；卡片拖出成独立 tab 时对话留在原 tab。
  - 单测：工具调用的目标不在 tab 的 AI 卡片集合里时被拒绝；断开、关闭中、EOF 的卡片在上下文里标为不可用、其工具不可调用，对话保留。
  - AI 相关 e2e 不改即通过。
- **切换 tab 的出入场动效**（2.5.7，第九批）：Z12 第一级已在 zenit 上游完成（`feat/app-extension-points` @ `db1fdd26`），先同步 `vendor/zenit`，再在这一步接入：浮动层按"是否属于当前 tab"驱动 `anchorCollapsed`，tab 条的 tab 用 `motionAnchor` 登记锚点；按设置项 `ui.float_card_transition` 选 `anchor` 或 `fade`（`fade` 的缩小部分等 Z12b，之前只淡出）；`ai.launcher` 展开成面板、面板收起回图标也走同一设置。设置项本身（配置键、外观页的 `RadioGroup`、test_id）与 PL4b 的会话记录卡片共用，谁先做谁加。用户可见的动效变化，截图与 e2e 按新基线采集。

- 退出标准：AI 相关 e2e 与截图相对 4c 之后的新基线不变；单测证明 `ai.chat` 放进独立 tab 或分屏被卡片宿主拒绝。
- test_id：不变。

4d（可选，随 P5 波次 C）单卡 tab 与组 tab 的容器代码路径合并（M8）。不做不影响 4a–4c′。

**PL5 插件视图 Yix 化**

内容：bmc 的 `views.zig`（2,510 行）、`editor.zig`（1,177 行）、`select_surface.zig` 与两个 `styles` 文件改写为 `view/*.yix` + `.yss` + view-model；fixture 同样处理；KVM 帧画面登记为 (b) 类例外。删除 `rules.zon` 的 `legacy_plugin`、`plugin_registry` 过渡层。

退出标准：`e2e/bmc_*`、`kvm_*`、`session_menu_kvm_native.ts`、`sidebar_kvm_route_native.ts`、`v02_fixture_native.ts` 全部通过；代表状态截图逐像素一致；`src/plugins/**` 在 check-arch 基线里只剩书面认可的例外；`zig build test-bmc`、`test-plugin-fixture` 的用例数不减。

test_id：bmc 与 fixture 的现有 id 全部冻结，Yix 化时带 id 的节点保持同一语义节点（Revamp 6.3 第 4 条）；id 表迁到各插件的 `model/ids.zig`。

**PL6 首个新插件与后续项**

- V0.5 网页连接按新模型实现：清单带 `summary`、`permissions`、`cards`；视图是 Yix；同一提交删除 `roadmap.zig` 里的 `web` 条目（否则注册失败）。验收标准是 V0.2 §9.0 的"后续接入"门槛：新增改动只在插件目录和 `plugins/index.zig`，公共业务模块 diff 为空。**显式豁免**（GLM C.f）：声明了 `native_code` 的插件，其 C / ObjC 源今天只能登记在 `build.zig` 里（bmc 的先例是 `build.zig:1053-1061`），所以对这类插件，验收口径是"除插件目录与 `plugins/index.zig` 外，只允许 `build.zig` 的该插件 C 源清单有改动"，并且这部分改动按 4.3 的审计 checklist 作为基础设施变更单独评审。web 插件如果需要 WKWebView 的 ObjC 桥，就落在这条豁免里。
- 可选：命令贡献（开放 `actions.zig` 的动作目录）、`actions.Capability` 改引用能力目录。
- 插件数据目录迁移（Q9 已判定：做，单独立项），不随 PL6 捆绑，排期另定。


### 5.3 回滚

每个阶段、每个子步骤一个可独立合并的包，回滚即 `git revert` 该包的合并提交。PL1 与 PL3 涉及清单结构，采取"先加后删"：新字段与旧字段并存一个包，消费者切换一个包，删除旧字段一个包。

### 5.4 发布说明

**M10 之后的 AI 日志改写到新文件名（降级只是看不到新对话，AI 不会整个失效）**

M10（ai-binding 包）起，会话日志每一行都是 `schema = 4`（归属 `{"tab":…}`），含 tab 绑定的执行日志写 `schema_version = 3`（`context.binding = {"tab":…}`、`context.content`）。M10 之前的版本读到这些内容会整份拒绝（实测先报 std.json 的 `UnknownField`），结果是旧版本里整个 AI 不可用（ai-followup 核对，证据 `ZeroWork-evidence/ai-followup/downgrade/`）。

ai-bugs 包起改为（用户判定）：

| 项目 | 规则 |
|---|---|
| 新文件名 | 会话日志 `ai-sessions.v4.jsonl`，执行日志 `ai/lifecycle.v4.json`（在原文件名上加 v4 后缀）；本版本只读写新文件 |
| 首次迁移 | 新文件不存在而旧文件（`ai-sessions.jsonl` / `ai/lifecycle.json`）存在时，"读旧写新"：按本版本规则完整校验旧文件内容，校验通过后写进新文件。会话日志在打开 AI 时迁移，执行日志在第一次生命周期工具调用时迁移 |
| 旧文件 | 只读，不加锁、不改写；迁移之后本版本不再读它 |
| 代码 | `session_journal.Journal.openMigrating`、`lifecycle_journal.Journal.openMigrating`；文件名常量 `session_journal.file_name / legacy_file_name`、`lifecycle_runtime.file_name / legacy_file_name` |

实测（ai-bugs，同一数据目录依次启动；旧版本为 M10 之前的 `4fc8c181` test-mode 构建，临时 worktree，跑完已删除；证据 `ZeroWork-evidence/ai-bugs/downgrade/`）：

| 阶段 | 结果 |
|---|---|
| 0 旧版本首次使用 | 写出 `ai-sessions.jsonl`（旧版本自己的对话） |
| 1 升级到本版本 | 打开 AI 时迁移出 `ai-sessions.v4.jsonl`；会话列表里有升级前的对话，新对话可回答；`ai-sessions.jsonl` SHA-256 不变，且不含 schema 4 行 |
| 2 降级回旧版本（数据目录另放入本版本写出的 `ai/lifecycle.v4.json`） | 启动正常；AI 入口出现、面板可打开、能看到升级前自己的对话、能回答；日志里没有 `UnknownField` / `InvalidSessionJournal`；两个 v4 文件 SHA-256 不变（旧版本只追加它自己的旧文件） |
| 3 再升级回本版本 | 升级前对话与升级后对话都在；降级期间在旧版本里新建的对话不在（迁移只发生一次） |

用户可见的说明（写进发布说明）：
- 本版本把 AI 对话记录与执行日志保存到新文件（`ai-sessions.v4.jsonl`、`ai/lifecycle.v4.json`），首次启动 AI 时自动从旧文件复制过来，旧文件保留不动。
- 降级到更早的版本后，AI 照常可用，只是看不到在新版本里创建的对话；重新升级后这些对话都还在。
- 降级期间在旧版本里新建的对话，重新升级后不会出现在新版本里（旧文件只在第一次升级时导入一次）。
- 已经用过 M10 之后、本包之前版本的数据目录：那段时间的 schema 4 行已写进旧文件名，本版本把它们一并迁到新文件，但旧文件按规则保持原样，所以更早的版本读它仍会失败（AI 不可用）。需要在更早的版本里用 AI 时，先退出应用，把 `ai-sessions.jsonl` 与 `ai/lifecycle.json` 移走备份（不要删除），本版本不再需要它们。

夹具与测试：`src/ai/test_fixtures/m10_downgrade/`、`src/ai/tests/m10_downgrade_fixture_tests.zig`（新增两条迁移测试：会话日志、执行日志各"只迁移一次、旧文件逐字节不变"，修复前均失败）。

---

## 6. 风险、开放问题与备选方案

### 6.1 风险

| # | 风险 | 应对 |
|---|---|---|
| R1 | 推导出来的能力数字与设计稿不一致，用户觉得"不像设计" | 这是"以代码为准"的直接结果；PL1 的求值断言先给用户看，设计稿按它回改 |
| R2 | 能力目录的准入规则太严，目录只剩很少几项，对照表显得单薄 | 宁缺毋滥；需要某项能力上界面，就先在清单层补真实声明并让门禁读它 |
| R3 | PL3 触及 `session_host.zig`（2,635 行）与 `application_host.zig`，回归面大 | "先加后删"三步走；V0.2 §8.0.3 的三协议行为回归基线逐项跑；真实引擎的验收 runner 照旧 |
| R4 | bmc 改经 `plugin_api` 后发现 facade 不够用（它现在直接 import `proto/ssh`、`config/hosts.zig`） | PL3 开始前先列出 bmc 的全部外部 import 并给每一条指定去处（经哪个 facade，或需要新增哪个 facade）；新增 facade 属于 API 2.1 的增量，逐项评审 |
| R5 | `CardSlot` 是命令式例外，与"视图 100% Yix"冲突 | 登记为 (b) 类例外，全仓只此一处；向 zenit 上游提"运行期组件槽"作为收回路径 |
| R6 | 卡片在放置之间移动时丢状态（焦点、滚动、输入法） | 契约规定状态在 view-model；4b 的退出标准包含移动后的状态保持；会话卡片在独立 tab 与分屏之间的移动沿用现有分组实现，不走重新挂载的新路径 |
| R13 | 删除 AI 停靠是默认形态的改变，所有 AI 截图基线失效，容易与并行的 AI 重构包的"逐像素一致"退出标准冲突 | 4c 作为独立包、单独的冻结窗口；合并前确认没有以旧基线为准的未合并 AI 包；基线重采并注明原因 |
| R14 | 删除 AI 条后，面板隐藏时看不到 AI 状态（尤其是"等待审批"），用户漏掉需要介入的事项 | 状态改由每个 tab 的 `ai.launcher` 承载并作为 4c-2 的退出标准；视觉按定稿 tfmv1 / Db7OS（待审批有着色与周期脉冲）；页签注意标记与菜单栏活动角标不变。注意非当前 tab 的图标看不到，那些 tab 的待审批仍靠页签注意标记提示 |
| R17 | 124 个 e2e 要改入口，容易出现"改了点击目标但脚本原本在等悬停预览的时序"或"图标在面板打开时隐藏、再点关不掉"之类的隐性失败 | 先在旧实现上加入 `ai.launcher`（此时与 `ai.strip`、`toolbar.ai` 并存），把 124 个脚本的入口改成它并跑通，再删 AI 条与 `toolbar.ai`；两步分开提交 |
| R22 | AI 不再有全局入口：空工作区或当前 tab 不能启动 AI 时，用户找不到 AI | 这是用户的判定（AI 不是全局概念）；快捷键与 `@ai` 在这种情况下按动作规则显示不可用原因 |
| R15 | 会话记录收敛时，`SessionTab.archived` 的分支遍布 `workspace.zig`、终端视图、AI、图标，漏删或误删影响实时会话 | H2 先让归档 tab 只含详情宿主且外观不变，H5 再删分支；删除前列出全部 `archived` 使用点并逐条归类 |
| R16 | 回放表面跨 feature 复用（history 嵌 terminal 的组件）导致两个 feature 的波次互相等待 | 只经 `features/terminal/mod.zig` 导出一个窄接口；H2 与 terminal 的分层步骤协调，接口先冻结 |
| R11 | 把入组条件从硬编码改成读约束时引入不等价（例如漏掉 `owned_pending`） | 约束只取代"是什么类型"的判断，`closing` / `owned_pending` 等状态条件原样保留；4a 的等价性单测逐状态对比 |
| R12 | 非会话卡片将来进入分屏后，被误当成会话组成员（收到广播、进入 AI 作用域） | roster 准入显式限定为会话卡片（M6），在放开任何非会话类型的 `split` 之前就落实并有单测 |
| R7 | PL2 改变了 P3 的"像素一致"退出标准 | 用户已同意（Q2）；P3 退出标准的例外条款见 6.2.1，执行时照此登记 |
| R8 | 权限声明给人"有沙箱"的错觉 | 文档、设置页帮助文案都写明这是声明与架构约束；不做授权弹窗 |
| R9 | 与并行进行的 P3–P5 包冲突（同改 `settings`、`workspace`、`rules.zon`） | PL 的包按 Revamp 的泳道规则走：改门面与 `rules.zon` 走主干泳道；PL1、PL3 各申请一个短冻结窗口 |
| R10 | 每帧轮询式的内容挂载（`safeTick`）在卡片类型变多后变慢 | 推测，未测量；4a 保持现有机制，只有出现证据再改为事件驱动 |
| R20 | 出入场动效依赖 zenit 上游（Z12 第一级已完成待同步；`fade` 模式的缩小部分依赖 Z12b） | 归属、范围、位置记录与动效解耦，先上线；同步前直接显隐，Z12b 前 `fade` 只淡出；不在下游手写近似动画 |
| R21 | 浮动卡片可以覆盖整个工作区后，挡住用户正在操作的终端或文件区，且卡片可以停在离所属内容很远的地方 | 卡片可以拖动、缩放、收起；切换 tab 自动收回；默认位置仍以所属内容区为锚点 |
| R18 | 用户以为"禁用"等于"从应用里移除"，或以为禁用后立即生效 |
 开关下方固定写明"重启后生效；代码仍随应用分发，只是不再加载和暴露入口"；已保存主机显示"已禁用"而不是"未知插件"（Q5） |
| R19 | 降级到不认识 `host.enabled` 的旧版本时，被禁用的插件在旧版本里重新可用 | 按 `config.zig` 的现有逻辑，`[[plugin_preferences]]` 条目只校验字符集、长度与重复（`:327-331`、`:367-371`），保存时整表写回（`:189` 起），所以旧版本会保留这条偏好但不读它（config-unknown-keys 合入后，这一点对新加的配置段同样成立；这条风险的实质不变：旧版本保留但不执行禁用。）
，所以再升级回来时禁用状态还在；这一点写进发布说明。不为此改用新的配置段，因为新段会让旧版本解析失败（`config.zig` 对未知段与未知键报错） |

### 6.2 需要用户拍板的开放问题

状态（2026-11-13）：Q1–Q12、Q5a–Q5c、Q14–Q17、Q20、Q21 已判定，浮动放置（第四批）、AI 能力归属卡片（第六批）与 AI 入口（第七批）的判定见 6.2.1；Q22–Q24 已判定（第八批）；Q18、Q19 暂缓。仍开放、执行到相应阶段再定的事项见 6.2.1 末尾。编号 Q13 未使用。

| # | 问题 | 建议 |
|---|---|---|
| Q1 | "计划中"分组要不要保留？ | **已判定**，见 6.2.1 |
| Q2 | "协议插件"面板是否跳过 P3 3e 的像素等价 Yix 化，直接在 PL2 按设计稿重建？ | **已判定：同意**，见 6.2.1 |
| Q3 | 终端、会话记录、AI 对话作为 feature 登记卡片类型，不搬进 `src/plugins`、不出现在"协议插件"页——认可吗？ | **已判定：认可**，见 6.2.1 |
| Q4 | AI 对话是否允许作为 tab 打开？ | **已判定：不允许**；且放置只保留浮动、删除停靠，见 6.2.1 |
| Q5 | 是否提供"禁用某个随应用提供的插件"的开关？ | **已判定：做，且提前到 PL1（机制）/ PL2（界面）**，见 6.2.1 |
| Q5a | 内置的 local、ssh、sftp 是否也能禁用？ | **已判定：不能**，见 6.2.1 |
| Q5b | 开关什么时候生效？ | **已判定：启用与禁用都在下次启动时生效**，见 6.2.1 |
| Q5c | 配置文件无法解析、读不出启用状态时，`bundled` 插件按启用还是按禁用处理？ | **已判定：按禁用处理（fail-closed）**，见 6.2.1 |
| Q6 | 设计稿里的 Ansible 行怎么办？代码与设计文档里都没有 | **已判定：不显示**；要进"计划中"须先有设计文档 |
| Q7 | 宿主 API 记为 2.1（次版本）还是 3？ | **已判定：2.1** |
| Q8 | 是否把"不做进程内运行期加载"写成硬性规则？ | **已判定：是**，写进本文与 AGENTS.md，并用 `ident:no-dylib` 机检 |
| Q9 | 是否把插件自有数据迁到每插件子目录？涉及已有 `bmc-management-v1.json` 的迁移 | **已判定：做，单独立项**，按 V0.2 §4.2.1 的迁移规则 |
| Q11 | 会话记录卡片是否允许进入 tab 内分屏？ | **已判定：先不允许**，模型保留开关 |
| Q12 | 是否连悬停预览、"钉住"状态和 AI 条也一并删除？ | **已判定：一起去掉**；主入口原定 `toolbar.ai`，已由第七批判定改为每个 tab 的浮动 AI 图标 `ai.launcher`，见 6.2.1 与 PL4c |
| Q14 | 终端里的"打开只读历史页"是否并入会话记录卡片？ | **已判定：不并入** |
| Q15 | 会话记录卡片能否同时开多张？ | **已判定：tab 可以开多张，浮动最多一张**；按 tab 归属理解为"每个 tab 最多一张"（2.5.7） |
| Q10 | 设计稿与代码不符的两处（各协议的能力数字；SSH 的"文件浏览与传输"被标为不支持）以推导结果为准，并回改设计稿——认可吗？ | **已判定：认可** |
| Q16 | `pane_manager.zig`、`shortcut_dispatch.zig`、`group_dispatch.zig` 只被测试引用（2.5.2 末尾），是否在 PL4a 之前连同它们的测试一起删除？ | **已判定：立项**，在 PL4a 之前删除，单独一个包，见 6.2.1 与 5.2 的 PL4a |
| Q17 | 把高风险解析器（RFB、JPEG、zlib、Redfish JSON）移到辅助进程，要不要现在就立项？ | **已判定：立项**，与 V0.5 并行，需要单独的设计文档；不并入插件化各阶段（6.4 的 X-2） |
| Q18 | 打包启用 hardened runtime，要不要立项？ | **暂缓**：用户这次未选，暂不立项；在 6.4 的 X-1 标为"已登记，暂缓" |
| Q19 | 4.3 的审计 checklist 写进 `AGENTS.md`，是否同意？ | **暂缓**：用户这次未选，暂不写进 `AGENTS.md`；内容先留在本文 4.3 |
| Q20 | 浮动卡片能否覆盖底部状态栏？ | **已判定：可以**。禁区只剩标题栏整条与展开时的侧栏，四边内缩 8pt（2.5.7） |
| Q21 | Q15 的"浮动最多一张"按 tab 归属理解后，不同 tab 可以各有一张浮动 `history` 卡片（同一时刻只显示一张）。认可这个理解，还是要"全窗口单例，从别的 tab 打开时把它的归属改到当前 tab"？ | **已判定：按 tab 归属，每个 tab 最多一张**（2.5.7） |
| Q22 | 会话记录卡片要不要提供 AI 上下文（例如把选中记录作为上下文）？ | **已判定：不自动提供**。初始不声明 AI 上下文；以后做成"用户选中一段、显式发给 AI"的动作（2.5.8） |
| Q23 | 浮动卡片计不计入"tab 能否启动 AI"的派生与上下文？ | **已判定：与放置无关**。只看卡片类型有没有声明 `ai`；浮在 tab 上的卡片同样属于这个 tab，声明了就参与（2.5.8 第 7 条）。"悄悄改变上下文"的顾虑由拉取模型处理 |
| Q24 | 统一绑定到 tab 后，单卡 tab 与组 tab 的上下文提示词文本要不要统一成一种？ | **已判定，问题消解**：上下文改为拉取，模型调用内置工具 `host.tab_context` 取当前 tab 下所有 AI 卡片的上下文，单卡与多卡同一套逻辑、同一种结构（2.5.8"拉取式 tab 上下文"；新包 M11） |


### 6.2.1 已判定

以下判定由协调者转达（2026-11-13），本文相应章节已按此更新。第二批（Q3、Q5–Q10）在 GLM 交叉评审之后判定，第三批（Q5a–Q5c、Q16–Q19）由用户以选择题拍板，都写在本节末尾。


**Q1 "计划中"分组：保留，只列有设计文档的条目。**

- KVM 已由 `bmc_ikvm` 实现（`src/plugins/bmc_ikvm/plugin.zig:105-129`），从"计划中"移除，只作为已注册插件显示。
- FTP / FTPS、VNC、RDP 既没有实现也没有设计文档，不列出。没有实现的证据：连接编辑器对 `.ssh`、`.sftp` 之外的协议一律返回 `error.UnsupportedProtocol`（`src/plugins/remote/editor.zig:163-167`）。
- "计划中"目前只有一项：网页连接（V0.5，`docs/DESIGN/V0.5_WEB_CONNECTION.md`）。
- 删除 `src/config/plugin_page.zig` 里的旧计划枚举 `PlannedProtocol` / `plans` 和假的预览状态 `PreviewKind` 及校验示例字段（PL1 第 3 条，已在范围内）。
- **附带建议（新增）**：`src/plugins/remote/editor.zig:44` 的 `Protocol` 枚举是 `{ ssh, sftp, scp, mosh, telnet, serial, ftps, vnc, rdp, kvm }`，其中只有 `ssh`、`sftp` 有实现，其余 8 个成员走到 `:166` 就是 `UnsupportedProtocol`。按"以代码为准"，这 8 个成员应当清理：从枚举里删除；将来哪一个要做，先写设计文档，再以路线条目的形式出现在 `roadmap.zig`，而不是作为一个可被选中却必然失败的枚举值留在编辑器里。清理放在 PL3 第 4 步（`plugins/remote` 归位 `features/connections/wizard`）里做，单独一个提交。执行前须核对：这些成员是否出现在协议选择器、已保存配置的解析（`hosts.toml` 里是否可能存在这些协议值）、e2e 与测试里；若已保存数据里可能有这些值，删除枚举成员要走兼容 codec 的"未知协议可列出、不可连接"路径（V0.2 §4.2），不能让旧配置解析失败。这一步本轮没有核实，列入第 7 节的待核实清单。

**Q2 协议插件面板：同意跳过 P3 的像素等价 Yix 化，直接按设计稿重建。**

对 `docs/ui-revamp/ARCHITECTURE_PLAN.md` 中 P3 的例外，执行时需要在该文档与 `YIX_EXCEPTIONS.md` 里同步登记：

| P3 原条款 | 例外 |
|---|---|
| 3e："9 个分类的面板逐个改 `.yix`，每个分类一个提交" | 协议插件分类不在 3e 内做像素等价改写；它的 `.yix` 实现由 PL2 交付，提交前缀为 `feat(settings)`，不是行为不变的重构 |
| 3f：删除旧实现与开关 | 3f 可以先行，但要保留协议插件面板所需的旧代码：`view/panes/settings_plugins.zig`、它依赖的 `settings_content_view.zig` 的 `Binding`、`settings_controls.zig` 相关部分，以及 `LegacyBody` 中协议插件那一份。这些在 PL2 合并时删除。若保留它们使 3f 无法干净收尾，则 3f 整体排到 PL2 之后 |
| P3 退出标准："设置窗口截图……与迁移前逐像素一致" | 协议插件页豁免逐像素一致。它在 P3 退出时仍是旧实现，截图自然不变；PL2 之后改为与设计稿对比 |
| P3 退出标准："PENCIL_MAP 设置窗口一节列出的节点 `design_diff` 分数不低于迁移前" | T5k96 在 P3 退出时沿用迁移前分数；PL2 的退出标准是 T5k96、KUKQ5、ibeKI 的分数达到其他面板的同等水平，且高于迁移前 |
| P3 退出标准："`features/settings` 在 `check-arch` 基线里没有条目" | 协议插件面板相关文件的基线条目（含 `ident:no-inline-style`、`ident:no-widget-internals`）允许保留到 PL2，P3 报告里逐条列出并标注"随 PL2 清零" |
| `YIX_EXCEPTIONS.md` 的 S-7 | 状态改为"过渡（协议插件部分随 PL2 消失）" |
| `e2e/settings_*` 全部通过 | 不变。`e2e/plugin_settings_v3_native.ts`、`e2e/v02_plugins_ui.ts` 在 P3 期间不改即通过，在 PL2 里按 5.2 的 test_id 说明重写 |

排序上的后果：PL1 不再受"必须早于 3e 的协议插件面板"约束（该面板已不在 3e 内），只需早于 PL2；PL2 可以在 P3 其余部分退出之后做。

**Q4 AI 对话：不能作为 tab 打开。**（原判定为"只允许停靠和浮动"，其中"停靠"已被下一条判定取代。）

按 2.5 的卡片模型，落为 `ai.chat` 的 `standalone_tab = false`。

**放置方式：只保留浮动，删除停靠。**用户原话："感觉保留 floating 就好了，docked 是不成熟的原始设计。"

- 卡片放置约束只剩三项：独立 tab、分屏（仅指 tab 内分屏）、浮动。方案里原有的"窗口级停靠槽位"已删除。
- `ai.chat`：独立 tab 否、分屏否、浮动是。AI 只以浮动方式呈现。
- 这会删除一项现有的、用户可见的行为：AI 面板默认停靠在主窗口右侧并占据布局。用户已明确要求删除。迁移步骤见 5.2 的 PL4c。
- **设计稿作废说明**：`docs/ui-revamp/PENCIL_MAP.md:49` 把 kuRaJ 映射为"AI 助手"，`:72` 记录的实现以"默认是 view island 内右侧的分栏 Pane"开头；`ai_pane_layout.zig:1` 也标注它实现的是"Island B v3 docked assistant pane（kuRaJ / w1mAz5 / N9ryVa `UsOQ2`）"。其中**停靠布局**部分（右侧分栏、宽 500、4pt 分隔条、会话窗格让出该列）已被本判定作废。kuRaJ 里与停靠无关的内容（步骤行、审批卡、运行方式 Tabs 等，`PENCIL_MAP.md:73-74`）不受影响。PL4c 执行时同步修改 `PENCIL_MAP.md`，并把 kuRaJ 的 `design_diff` 基线改为只比较卡片内部。
- **Q12 已判定：一起去掉。**AI 条（`ai.strip`）、悬停预览、"钉住"状态，连同停靠布局一并删除。背景事实（供评审核对）：这三样在代码里属于浮动模式而不是停靠——悬停预览在停靠时被显式禁用（`ai_host.zig:2972-2973`），`dock_state.Mode { hidden, preview, pinned }` 是面板的显隐状态机，AI 条是打开面板的入口并显示窗格的 AI 状态（`ai_host.zig:3033-3036`）。所以这是在删除停靠之外，对浮动模式再做的一项用户可见的行为变更；删除清单、入口、状态机收敛、e2e 与 test_id 见 PL4c。
  - **主入口**：~~标题栏的"AI 助手"按钮，test_id `toolbar.ai`（`src/features/shell/host/chrome_mount.zig:106-111`）~~。**已被第七批判定取代**：删除 `toolbar.ai`，主入口改为每个 tab 的浮动 AI 图标 `ai.launcher`（本节末尾第七批、2.5.8）。
  - **其余入口核对结果**：快捷键动作 `toggle_ai`（动作 ID `assistant.toggle`，`src/host/actions.zig:144`）；应用指令 `@ai`（`actions.zig:188`）；右键菜单的"问 AI"映射到同一个动作（`src/features/workspace/model/context_menus.zig:68`）。加上工具栏按钮共四个入口，没有发现缺口；文件会话今天本来就不显示 AI 条（`ai_host.zig:3016` 的注释），靠的就是这些入口。没有核对的两点：`toggle_ai` 的默认按键是什么、macOS 菜单栏里有没有对应菜单项，执行者补查，缺菜单项就补一个指向同一动作的。
  - **删除 AI 条带来的一个功能缺口（需要补上，否则是退步）**：AI 条除了是入口，还在面板隐藏时显示该窗格 AI 的状态（待审批、运行中、失败、有新回答，`ai_strip_styles.project`，`ai_host.zig:3033`）。删除后，面板隐藏时用户看不到"AI 在等你审批"。方案原先的处理是让 `toolbar.ai` 承载这个状态；**第七批判定改为由每个 tab 的 `ai.launcher` 承载**（五种状态：待审批、运行中、失败、待核实、有新回答）。视觉按定稿（Pencil XqqLV 的 tfmv1 / cVXd5 / Db7OS）；页签上已有的注意标记和菜单栏活动角标不变。

**Q11 已判定：先不允许。**`history` 卡片初始不能放进 tab 内分屏；模型里保留 `split` 这个开关，以后放开只改一个值。

**Q14 已判定：不并入。**终端里的"打开只读历史页"仍然是终端卡片的内部状态。

**Q15 已判定：tab 可以开多张，浮动最多一张。**（第四批判定之后按 tab 归属理解为"每个 tab 最多一张"，见本节末尾与 2.5.7。）

**会话记录：合并为一张 `history` 卡片，内部是列表 + 详情。**用户原话见 2.5.4。

- 列表与回放不再是两种卡片；归档 tab、回放 tab、全窗口浮层都改为这张卡片的内部状态。
- 放置约束：独立 tab 是、浮动是、分屏初始为否（Q11 改为针对这一张卡片）。
- 迁移步骤、持久化数据、e2e 与 test_id、view-model 划分见 5.2 的 PL4b。

**tab content 模型（用户补充意见，2026-11-13）：tab 与 tab body 里的分屏是同一个东西，卡片类型配置约束。**

已据此重写 2.5，并相应更新 5.2 的 PL4。与修订前的差别见 2.5.6。

---

**第二批判定（2026-11-13，GLM 交叉评审之后）**

**Q3、Q6、Q7、Q8、Q9、Q10：用户没有异议，按作者与 GLM 一致的建议执行。**

| # | 判定 | 落到本文的位置 |
|---|---|---|
| Q3 | 终端、会话记录、AI 对话作为 feature 登记卡片类型，不搬进 `src/plugins`，不出现在"协议插件"页 | 2.5.4；登记时序见 2.5.3 |
| Q6 | 设计稿里的 Ansible 行不显示；要进"计划中"必须先有设计文档 | 1.8、2.6 |
| Q7 | 宿主 API 记为 2.1（次版本），不升 3 | 2.2；API 面的范围与版本规则见 3.1 |
| Q8 | "不做进程内运行期加载"是硬性规则，写进本文与 `AGENTS.md`，并由 `ident:no-dylib` 机检；措辞覆盖 MCP 这条进程外通道 | 3.3、4.5 |
| Q9 | 插件自有数据迁到每插件子目录，单独立项，按 V0.2 §4.2.1 的迁移规则；不并入 PL6 | 4.4、5.2 的 PL6 |
| Q10 | 能力数字与 SSH 文件能力以推导结果为准，回改设计稿 | 1.8、2.3、PL2 |

**Q5 已判定：做。提前提供"随应用提供"插件的禁用开关，不推到 PL6。**用户原话："做Q5"。即采纳 GLM 的建议：本方案不做授权弹窗，这个开关就是用户唯一能自己动手缩小攻击面的手段，而 bmc 解析 RFB、Redfish、JPEG 的代码恰好是最大的一块。

*适用范围*

- 只针对 `origin = .bundled` 的插件。生产构建里目前只有 `bmc_ikvm`；测试构建里的 `fixture_probe` 也是 `bundled`（`src/plugins/fixture_probe/plugin.zig:211`），e2e 用它验证；将来的 web 插件同样适用。
- **内置的 local、ssh、sftp 不能禁用（Q5a 已判定，按建议）**。理由：
  1. 缩小不了多少攻击面。SSH 协议栈、本机进程、文件传输引擎都在 core（`src/proto/ssh`、`src/local`、`src/transfer`），这三个插件只是适配器；app 与 core 今天还直接引用它们（`application_host.zig:94`、`:245-247`；`session_host.zig:363`）。不注册适配器，引擎仍被别的路径引用。
  2. 三者互相牵连。SSH 的辅助只读与辅助传输（`integration.auxiliary_readonly`、`auxiliary_transfer`）依赖文件引擎；SSH 与 SFTP 共用连接编辑器和跳板路由。单独禁用其中一个，组合状态要另行定义和测试。
  3. local 是唯一带快速创建的插件（`linked_plugins.zig:86` 的 `quick_create`），禁用后应用可能没有任何可创建的会话。
  4. 与 2.4 原先"内置三项不可禁用"的立场一致。PL3 之后（三者各有清单、core 不再反向 import 插件）可以重新评估，届时最可能有意义的是单独禁用 SFTP。

*禁用的语义*

| 方面 | 规则 | 理由 |
|---|---|---|
| 注册 | **不注册**：启动时不调用插件的初始化（bmc 今天在 `application_plugins.zig:40` 调 `bmc.Plugin.init`），也不把它的清单与 renderer 交给注册表。不采用"注册了但不可创建" | 注册表是启动时一次性发布的不可变快照（`plugin_registry.zig:226` 的 `publish`；`app/main.zig:87-89`）。不注册之后，创建入口、协议选择器、服务、通知定义（`main.zig:90` 从快照登记）都按已有的"清单不在快照里"路径消失，不需要在每个消费者那里加判断，也就不会"漏一处" |
| AI 工具 | **从工具目录移除** | 工具定义与绑定来自清单（`plugin_registry.zig:250` 的 `validateBindings`），清单不注册就不进目录；`ai_context` 摘要也不再提供。AI 对话历史里此前的工具调用记录仍可阅读，但不能再次执行 |
| 已打开的会话 | 本次运行内不受影响，直到用户正常退出应用 | 切换在下次启动时生效（Q5b），本次运行内不拆正在运行的协议栈；退出走现有的关闭确认流程，不强制结束任何会话 |
| 已保存的主机 | 保留，**留在原分组的原位置**；可列出、可导出、可删除；不可连接、不可测试连接；"编辑"保留但只能改通用字段（名称、分组等），协议载荷原样保留、不解码也不改写（定稿 qQaos / RfJyL、41 号说明稿） | 沿用 V0.2 §4.2 对未知插件的既有规则（`V0.2_PLUGIN_HOST.md:109`）。与未知插件只差原因文案："BMC · iKVM 已禁用，可在 设置 → 协议插件 中启用"，而不是"未知插件"。区分依据是"已链接插件表"（PL1 第 6 条）里有这个 ID |
| 插件自有数据 | 不打开、不删除、不迁移（今天是 `bmc-management-v1.json`） | 重新启用后要靠它继续核对"结果待确认"的管理操作。代价是禁用期间这些操作不会被核对，开关说明里要提一句 |
| 插件偏好 | 保留 | 键本来就带插件 ID，重新启用后原样生效 |
| 依赖 | 如果有其他已启用的插件依赖它 `provides` 的 API，拒绝禁用并说明原因 | 否则下次启动 `publish` 会因缺依赖整体失败。今天没有这种依赖，规则先写上 |

*如实说明：禁用不是卸载*

编译期链接意味着，禁用只是"不初始化、不注册、不暴露入口"。插件的 Zig 代码、它的 C 源（`tls_shim.c`、`zlib_shim.c`、`jpeg.c`，以及 `src/platform/bmc_tls_trust.c`）、链接进来的 mbedtls 与 zlib，仍然在同一个可执行文件里，仍然随应用一起签名分发。这些 C 文件里没有 `__attribute__((constructor))` 之类在加载时自动执行的代码（已检查），Zig 也没有静态构造，所以不被调用就不会执行。开关旁的说明文字和帮助文案都要写明这一点。

*生效时机（Q5b 已判定，按建议）*

启用与禁用两个方向都在下次启动时生效：

- 禁用无法立即彻底生效。注册表快照在启动时发布后就不再变化；要在运行期撤下一个插件，需要新增"替换快照、所有消费者重新绑定、正在运行的会话收尾"一整套机制，不值得。
- 也不建议"立即停止新建、重启后完全卸载"这种半状态。它会多出一个"已禁用但仍在运行"的状态，每个入口都要单独处理，测试面翻倍。
- 重新启用同样需要重启，因为插件在本次运行里根本没有初始化。
- **定稿保留"立即重启"按钮**（NHr2L / DzPbO）。应用里今天没有"重启应用"动作（在设置的 model 和 `src/update` 里都没有找到 relaunch），所以这是新增能力：按钮触发**正常的退出流程**（与 ⌘Q 相同的关闭确认，有未保存内容或运行中的会话时照常询问，不强制结束任何进程），退出完成后再启动同一个 `/Applications/ZeroWork.app`。退出协调可复用自动更新已有的关闭协调（`src/update/close_coordinator.zig`）；"退出后再启动"由谁执行（自动更新的独立辅助程序是否已有这一步，或用系统的重新打开机制），执行时核对后选定。用户在关闭确认里取消时，什么都不发生，开关保持"重启后生效"。

*配置*

- **存放位置**：`config.toml` 的 `[[plugin_preferences]]`，条目为 `plugin_id = "bmc_ikvm"`、`key = "host.enabled"`、`value = "false"`。没有这一条就表示启用；重新启用时删除这一条，而不是写成 `true`，让配置保持最小。
- **为什么不用新段 `[plugins] disabled = [...]`**（2.4 的原方案；第九批之后按 config-unknown-keys 重新评估）：当初选 `[[plugin_preferences]]` 的主要理由是兼容——基线的 `config.zig` 遇到未知段、未知键直接报错（`config.zig:481-482` 返回 `InvalidSection`，未知键返回 `UnknownKey`），新段会让旧版本整份配置解析失败。config-unknown-keys 合入后这条理由不再成立（未知段会被跳过并原样保留）。**结论维持不变**，理由换成：① 启用状态本来就是"每个插件一份"的设置，`[[plugin_preferences]]` 已经按插件 ID 分条存放，加一个保留前缀 `host.` 就够，不需要为它新开配置段和解析分支；② 它与插件的其他偏好放在一起，删除、导出、往返都走同一条现有路径；③ 早于这项修复的版本同样能读（`[[plugin_preferences]]` 是它们认识的格式）。
- **`host.` 前缀留给宿主**：注册校验拒绝插件把自己的偏好字段命名为 `host.*`（2.2 第 7 条），不会与插件自己的偏好冲突。
- **迁移**：今天没有任何禁用状态，没有旧数据需要迁移。
- **读取时机**：必须在构造插件 bundle（`app/main.zig:87`）之前读到。今天完整的运行配置要到创建窗口时才加载（`app/main_window.zig:72-76`），所以要么提前单独读这一项，要么把配置加载整体前移，由执行者选择；两条路径读到的值必须一致，用单测覆盖。
- **配置无法解析时（Q5c 已判定，按建议）**：`bundled` 插件按禁用处理（fail-closed），协议插件页说明"配置无法读取，随应用提供的插件暂未加载"。理由是这个开关的用途就是缩小攻击面，配置损坏时静默加载用户关掉的解析器，正好违背用户的意图；内置三项不受影响。代价是配置损坏期间 KVM 不可用。

*界面*

**设计稿已定稿**：Pencil 区域 XqqLV 的稿 2。详情页 Jm2fZ（已启用）、SH1gb（改了未保存）、NHr2L（待重启，浅色）、B0QXg6（已禁用，浅色）、DzPbO（待重启，深色）、IeCzY（已禁用，深色）；列表 UuE31（含已禁用行）、gTZVO（列表行各状态）；侧栏与右键菜单 qQaos / RfJyL；连接向导 YWqSG；规则说明 Pzzo6。PNG 在 `~/work/ZeroWork-evidence/design-r2/`（31–41 号）。

- **位置**：PL2 的单协议页上的"状态"分组，一行"启用"，控件是 zenit 原生的 `Switch`。只有 `bundled` 插件显示这一行，内置三项不显示（Q5a）。
- **状态流转**（41 号说明稿）：已启用（Jm2fZ）→ 拨动开关 → 改了未保存（SH1gb，沿用设置窗口的保存栏：保存 / 撤销）→ 保存 → 待重启（NHr2L / DzPbO：warning 标签"重启后禁用"或"重启后启用"，说明文字与"立即重启"按钮）→ 重启 → 已禁用（B0QXg6 / IeCzY）。在待重启状态把开关拨回去并保存，回到原状态，不需要重启。
- **开关旁的说明**："重新启动 ZeroWork 后生效。禁用后不再加载这个插件，它的连接、AI 工具和通知都不可用；代码仍随应用分发。"（确切措辞以定稿为准。）
- **列表**（UuE31 / gTZVO）：已禁用的插件仍列在"随应用提供"分组里（数据来自"已链接插件表"），标"已禁用"，不显示能力数；待重启的行标"重启后禁用 / 重启后启用"。能力对照表不列已禁用的插件（对照表是对注册表快照求值的，2.3）。单协议页上能看到身份、权限声明与开关，能力区显示"已禁用"。
- **侧栏与右键菜单**（qQaos / RfJyL）：被禁用插件的已保存主机**留在原分组原位置**，以禁用样式显示并带原因提示；右键菜单里"连接"置灰（带原因），"编辑…"和"删除…"保留。"编辑"只能改通用字段（名称、分组等），因为插件没有初始化，它的协议编辑器不可用；协议载荷原样保留。
- **连接向导**（YWqSG）：新建连接时，协议下拉里仍列出被禁用的插件，作为**禁用选项**（zenit `Select` 原生支持，`SelectOption.disabled`，`vendor/zenit/src/ui/components/select/mod.zig:43-46`），标"已禁用"，不能选中。这要求向导的协议列表取自"已链接插件表"而不是只取注册表快照。
- **上游缺口**：设计系统里的 Card Type 组件没有禁用样式（41 号说明稿），登记为上游缺口 Z13（`docs/ui-revamp/ARCHITECTURE_PLAN.md` 3.5）。向导用的是下拉的禁用选项，不依赖它，所以不阻塞 PL2。
- 与 KUKQ5 原稿的差异（新增状态分组与开关行）以定稿为准，写进 `PENCIL_MAP.md`。

*阶段、退出标准、test_id 与 e2e*

最早可行的安排：**机制放在 PL1，界面开关放在 PL2**。不把开关加到今天的命令式面板上，因为这个面板在 PL2 会按设计稿整体重建（Q2），在旧代码上加开关等于写两遍。PL1 合并后，用户可以通过编辑配置文件使用这个功能；PL2 合并后有界面。

PL1 的退出标准（单测）：
- `host.enabled = "false"` 时，注册表快照里没有该插件；它的工具定义不在 AI 工具目录里；它的通知定义没有登记；协议选择器只把它列为禁用选项、不可选中；插件的初始化函数没有被调用。
- 被禁用插件的已保存主机：只允许修改通用字段，协议载荷字节不变。
- 对内置三项写 `host.enabled = "false"` 不生效，并记一条警告。
- 被禁用插件的已保存主机：打开时返回"已禁用"错误（区别于现有的 `UnknownPlugin`），载荷字节不变，可以删除与导出。
- 有其他插件依赖它时拒绝禁用。
- 配置无法解析时，`bundled` 插件不初始化、不注册，协议插件页显示原因（Q5c）。
- 插件偏好键以 `host.` 开头时注册被拒绝。
- 默认配置（没有 `host.enabled` 条目）下，全量 e2e 与截图不变。

PL2 的退出标准：
- 新增 `e2e/plugin_disable_native.ts`，在 `-Dplugin-fixture` 的测试构建里用 `fixture_probe` 跑，不依赖真实 BMC：打开 设置 → 协议插件 → fixture 单协议页，关闭开关，断言提示出现；正常退出，用同一个数据目录重新启动；断言列表行显示"已禁用"、协议下拉里 fixture 是禁用选项、已保存的 fixture 主机留在原位置、显示已禁用原因、右键菜单"连接"置灰而"编辑""删除"可用；打开开关，再重启，断言全部恢复，已保存主机可以连接。
- `bmc_ikvm` 跑同一流程的只读部分（不连接真实设备）：禁用后，侧栏里的 KVM 主机显示已禁用原因。
- "立即重启"：点击后走正常的关闭确认；在确认里取消时应用不退出、状态保持"重启后生效"；确认后应用退出并重新启动，启动后插件处于新状态。e2e 驱动重启的方式由执行者按测试框架定（可以只断言"发起了正常退出并登记了再启动"）。
- 改了未保存（SH1gb）时撤销能恢复原值；待重启时拨回并保存能回到原状态。
- 与 Jm2fZ / SH1gb / NHr2L / B0QXg6 / DzPbO / IeCzY / UuE31 / gTZVO / qQaos / RfJyL / YWqSG 的 `design_diff` 有记录。
- 内置三项的单协议页没有开关：断言 `settings.plugin.local.enabled` 不存在。
- 明暗主题下开关行各一张截图。

test_id（由 `model/ids.zig` 生成）：
- `settings.plugin.<id>.enabled`：开关本身。
- `settings.plugin.<id>.enabled.hint`：开关下方的"重启后生效"提示。
- `settings.plugin.<id>.restart`："立即重启"按钮。
- `settings.plugin.<id>.disabled`：列表行上的"已禁用 / 重启后禁用"标记。
- `sidebar.host.unavailable`：已保存主机上的不可用原因。如果侧栏已有通用的不可用原因节点，就复用它，执行时核对。

*安全：能缩小什么，不能缩小什么*

能缩小：
- **远端数据解析器不再被调用**：RFB 帧、Redfish JSON、经 `jpeg.c` / `zlib_shim.c` 的图像解码、bmc 自己的 TLS 路径（`tls_shim.c`）。没有会话、没有连接测试、没有编辑器，远端字节就进不了这些代码。
- **AI 路径**：bmc 的 8 个工具（`tools.zig:21-30`，其中 2 个 `remote_input`、2 个 `observe_image`）不在工具目录里，提示注入无从调用；它的 `ai_context` 摘要也不再发给 AI 服务商。
- **后台活动**：插件的工作线程、管理日志的文件句柄、帧预算都不再创建。
- 已保存主机的载荷不再被插件的 codec 解码。

不能缩小：
- **代码仍在进程里**。进程内别处的内存破坏漏洞，仍然可以把执行流引向这些已链接的代码（例如代码复用攻击），禁用改变不了这一点。
- **供应链与审计面不变**。被禁用插件的源码、vendored 的 mbedtls 与 zlib 仍在签名后的可执行文件里，仍要按 4.3 的 checklist 审计。
- **内置三项与 core 的攻击面不变**：SSH 协议栈、终端解析（libghostty-vt）、与 AI 服务商的通信、MCP 子进程都不受这个开关影响。
- **防不了恶意插件代码**。如果插件代码本身是恶意的，问题出在审计环节；编译期链接下，"禁用"挡不住构建时就已存在的东西（例如 C 代码里的加载时构造函数——今天没有，但这要靠审计保证，不能靠开关）。

---

**第三批判定（2026-11-13，用户以选择题拍板）**

| # | 判定 | 落到本文的位置 |
|---|---|---|
| Q5a | **按建议：local、ssh、sftp 不能禁用。**开关只对 `bundled` 插件提供；对内置三项写 `host.enabled = "false"` 不生效并记警告 | 2.4；本节 Q5"适用范围""界面"；PL1 退出标准 |
| Q5b | **按建议：启用与禁用都在下次启动时生效。**本次运行内不改变已有会话与入口，界面提示"重启后生效"；定稿另有"立即重启"按钮，走正常的退出确认（6.2.1 Q5 的"生效时机"） | 本节 Q5"生效时机" |
| Q5c | **按建议：配置损坏、读不出启用状态时按禁用处理（fail-closed）。**内置三项不受影响；协议插件页说明原因 | 本节 Q5"配置"；PL1 退出标准 |
| Q16 | **立项。**`pane_manager.zig`、`shortcut_dispatch.zig`、`group_dispatch.zig` 这三个只服务测试的文件，在 PL4a 之前删除，单独一个包；删除前把仍有价值的测试用例改挂到运行期实现 | 2.5.2 末尾；5.2 的 PL4a"前置包" |
| Q17 | **立项。**高风险解析器移到进程外（6.4 的 X-2），与 V0.5 并行，需要单独的设计文档；不并入插件化各阶段 | 4.1；6.4 的 X-2 |
| Q18 | **暂缓。**用户这次没有选择，hardened runtime 暂不立项，在 6.4 的 X-1 标为"已登记，暂缓"。4.5 第 4 条的更正（"今天的签名挡不住运行期加载"）保留 | 4.5；6.4 的 X-1 |
| Q19 | **暂缓。**用户这次没有选择，审计 checklist 暂不写进 `AGENTS.md`，内容先留在本文 4.3，作为评审插件相关提交时的参照；PL1 不含这一步 | 4.3；5.2 的 PL1 第 7 条 |

**第四批判定（2026-11-13）：浮动放置的范围与切换 tab 时的收回**

用户原话："floating 模式下，是整个window都可以拖拽停放，现在是限制在tab content里了。只是切换顶部Tab后，它们会有一个快速收回到原tab的动效。像macos的dock那个最小化一样。"

- **范围**：浮动卡片的拖拽与停放范围是整个窗口内容区，可以越过 tab content 的边界。禁区是标题栏整条（44pt，原生拖动带、tab 条、工具栏与侧栏收起时的红绿灯都在里面）与展开时的侧栏；状态栏可以覆盖（Q20）；四周内缩 8pt。今天的实现把范围限制在所属内容区（`float_model.zig` 的 `safeBounds`，`nav_host.zig:585-591` 传入 `ownerBounds()`），要改。
- **归属**：浮动卡片仍属于打开它的 tab。切换顶部 tab 时，不属于当前 tab 的浮动卡片快速收回到所属 tab 在 tab 条上的位置（类似 macOS Dock 最小化的 genie）；切回所属 tab 时从该位置展开，回到原来停放的地方。
- **位置记录**：窗口内容坐标；`desired`（用户放下的位置）与 `clamped`（夹取后的位置）分离；窗口缩放、侧栏切换、全屏、跨显示器都只是浮动区域变化，按同一规则夹回可见区域，区域变大后回到 `desired`；不记录屏幕坐标；重启不恢复（与今天相同）。
- **动效是 zenit 原生能力**：已核实 vendor/zenit 的 `node_animator`、`transition`、`snapshot_transition`（只有 `dissolve`）、`overlay_transition`（锚点附近的进出预设）、`tab_motion`（iOS tab 选中镜片）和 `ContentWarp`（玻璃透镜形变）都不能直接承载 genie 或"收向远处锚点"。登记上游缺口 Z12；落地之前只做直接显隐，不在下游手写动画。（第九批更新：Z12 第一级已在上游完成，`fade` 模式另需 Z12b，见 2.5.7。）
- **Q15**：仍然成立，按 tab 归属理解为"每个 tab 最多一张浮动 `history` 卡片"；与原先"全窗口单例"写法的差别见 2.5.7，Q21 已按此判定。
- 落到本文：2.5.1、2.5.3（`float_per_tab`）、2.5.5 的 M7、2.5.6、2.5.7（完整规则）、PL4b（浮动行为、退出标准、e2e 与 test_id）、PL4c（新增 4c-3、默认位置、`ai_float_geometry_native.ts` 的断言、4c′ 接入动效）。

**第五批判定（2026-11-13）**

| # | 判定 | 落到本文的位置 |
|---|---|---|
| Q20 | **浮动卡片可以覆盖状态栏。**可停放区域包含底部状态栏；禁区只剩标题栏整条与展开时的侧栏；四边再内缩 8pt。被压住的那段状态栏入口点不到，用户移开或收起卡片即可 | 2.5.6、2.5.7；PL4b 退出标准；PL4c 的 4c-3、`ai_float_geometry_native.ts` 的断言 |
| Q21 | **按 tab 归属，每个 tab 最多一张浮动 `history` 卡片**（按建议）。不采用"全窗口单例、打开时改归属" | 2.5.3 的 `float_per_tab`、2.5.7、PL4b |

另外，上游缺口 Z12（"收向锚点 / 从锚点展开"的过渡）已登记进 `docs/ui-revamp/ARCHITECTURE_PLAN.md` 3.5 的上游缺口表。

**第六批判定（2026-11-13）：AI 能力只在卡片上配置，tab 能否启动 AI 是派生的**

用户原话："我感觉其实我们一个tab它下面是有n个cards的，应该是判断只要这个tab下有一个card是支持AI组装上下文的，那这个Tab就是可以启动AI的，所以应该还是只有card上有这个配置，Tab上能不能插入AI是派生的。"

- **AI 能力只在卡片类型上声明**：`CardTypeDef.ai: ?CardAi`，包含上下文提供者与"能作为哪些工具的目标"。tab 上没有任何 AI 配置；清单级的 `integration.ai`、`ai_context`、`ai_adapter_factory` 移到卡片类型后删除。
- **tab 能否启动 AI 是派生的**：tab 里只要有一张卡片声明了 `ai`，这个 tab 就能启动 AI（第八批 Q23 明确：与放置方式无关，浮动卡片也算）。
- **统一绑定到 tab**：AI 对话绑定 tab 这个卡片容器，不再区分单会话 tab 的 `.session` 与会话组的 `.group`；单卡 tab 是特例。上下文由 tab 里所有 AI 卡片合并组装，在现有 `group_context` 的基础上泛化（身份行预留、平均分配预算、16 上限、钉住卡片只影响顺序）；工具作用域是这些卡片声明的工具，每次调用显式指定目标卡片。
- **唯一事实来源**：`supportsAssistant`、上下文组装、`assistantToolsAvailable` 都从卡片的 AI 声明派生；运行时状态门禁（断开、关闭中、EOF 等时工具不可用、对话保留）按卡片保留。原先"两处门禁读法不一致"的开放问题就此消解。
- **权限**：插件定义的卡片类型声明 AI 上下文或工具时，所属插件必须有 `ai_integration` 权限（2.2 第 4 条）。
- **迁移**：运行期 `.session` / `.group` 改为 `.tab`；已保存的对话因为重启后本来就全部成为历史对话，不需要改写旧绑定，旧行只读回放，新行写 `schema = 4`。
- **阶段**：PL1 先把两处门禁收敛到同一个谓词（行为不变）；PL4a 的 M9 把 AI 能力移到卡片类型（行为不变）；4c′ 的 M10 统一绑定到 tab（行为不变，提示词文本用 golden 测试固定）。
- 落到本文：2.2 第 4 条、2.3、2.5.2、2.5.3、2.5.4、2.5.5（M9、M10）、2.5.7、2.5.8（完整设计）、PL1、PL4a、4c′。
- 带出的问题 Q22（会话记录卡片是否提供 AI 上下文）、Q23（浮动卡片是否计入派生）、Q24（是否统一提示词文本）已在第八批判定。

**第七批判定（2026-11-13）：AI 入口改为每个 tab 的浮动图标，删除 `toolbar.ai`；标题栏工具按钮用 zenit 原生默认尺寸**

用户原话："顶部这里可能不放AI按钮了，它本来就不是全局的概念。而是floating 在tab body里，如果打开了，floating AI icon就不显示。"

- **删除标题栏的 `toolbar.ai` 按钮**，推翻原先"以 `toolbar.ai` 为 AI 主入口"的设定（Q12 判定里的主入口、PL4c 的入口与状态承载都随之改写）。AI 不是全局入口。
- **AI 入口是每个 tab 自己的浮动 AI 图标 `ai.launcher`**，浮在 tab body 里；只在 tab 能启动 AI 时出现（2.5.8 的派生规则）；AI 面板打开时隐藏，收起后重新出现。
- **状态显示统一移到这个图标**：待审批、运行中、失败、待核实、有新回答。
- **其余入口保留**：`toggle_ai`、`@ai`、右键菜单"问 AI"，都作用于当前 tab。
- **e2e**：原计划"34 个 e2e 改成点 `toolbar.ai`"改为点 `ai.launcher`。复核后要改的是 124 个：用 `ai.strip` 的 34 个加用 `toolbar.ai` 的 94 个，重叠 4 个。`toolbar.ai` 从两份 test_id 清单删除，新增 `ai.launcher`（PL4c 的"e2e 与 test_id"）。
- **设计稿已定稿**（2026-11-13 补记）：XqqLV「ZW · 插件化补稿 2026-11-13」，状态矩阵 tfmv1 / cVXd5，规则 Db7OS / wqZ1s，tab 上下文 XZGS9；要点写在 2.5.8 的"入口"。图标展开成面板的过渡遵守设置项 `ui.float_card_transition`（第九批，2.5.7）。
- **标题栏工具按钮一律用 zenit 原生 ghost 图标按钮的默认尺寸**（定稿 p773F9：zenit 默认的 md 图标按钮，32×32、图标 16、圆角 6）：去掉 `shell_styles.titleToolbarButton`（`src/features/shell/view/shell_styles.zig:166-170`，把按钮改成 24×24、圆角 6）对尺寸的覆盖。调用点有 7 处：`chrome_mount.zig:77`、`:92`、`:110`、`:119`，`workspace_chrome.zig:47`、`:238`，`app/main_window.zig:733`。这是界面像素的变化，已写进 `docs/ui-revamp/ARCHITECTURE_PLAN.md` 的 P4 清单与 `docs/ui-revamp/NATIVE_AUDIT.md` 清单 3.1；`ssh_status_host.zig:11` 与 `ssh_status_host_tests.zig:508` 的注释和断言依赖 24×24，随之更新。
- Q22、Q23、Q24 不受影响，仍待判定。
- 落到本文：2.5.7（禁区说明）、2.5.8（"入口"）、PL4c（4c-2 的范围、入口、e2e 与 test_id、退出标准）、R14、R17、R22、Q12。

**第八批判定（2026-11-13）：Q22、Q23、Q24**

| # | 判定 | 落到本文的位置 |
|---|---|---|
| Q22 | **不自动提供。**会话记录卡片初始不声明 AI 上下文；以后做成"用户选中一段、显式发给 AI"的动作，走用户主动附加的附件机制，单独立项 | 2.5.8 的卡片表与"会话记录卡片不自动提供 AI 上下文" |
| Q23 | **与放置方式无关。**用户原话："算不算ai上下文只看这个card类型有没有声明是否可以给AI上下文啊，跟浮动不浮动有什么关系？"卡片是否参与 tab 的 AI 上下文、是否让 tab 能启动 AI，只看卡片类型是否声明 `ai`；浮在 tab 上的卡片同样属于这个 tab。删除了"浮动卡片不计入"的建议；"浮动卡片悄悄改变上下文"的顾虑由 Q24 的拉取模型处理 | 2.5.8 第 7 条 |
| Q24 | **上下文改为拉取。**用户原话："单卡和分屏卡不都是一样的收集逻辑吗？我理解是我们给到AI agent一个内置Tool，获取当前tab下的ai上下文。不是吗？"新增内置工具 `host.tab_context`，返回当前 tab 下所有声明了 `ai` 的卡片的上下文，每张一条（卡片引用、类型、身份、放置、可用状态、内容），单卡与多卡同一套收集逻辑；预算与截断沿用 `group_context` 的规则。原先"要不要统一两种文本"的问题消解 | 2.5.8"拉取式 tab 上下文"；2.5.5 的 M11；4c′ |

据此处理的细节（详见 2.5.8）：
- **复核修正**：本文先前把 `ai_group_context` 描述为现有的合并上下文形态。复核发现它和 `ai_session_context` 这两个推送式组装函数只被测试引用；生产请求的系统提示只含执行规则与 `<host_session_facts>` 元数据（最多 8 个会话，无内容），内容今天就靠 `host.read_terminal` 等工具拉取。所以拉取模型是现状的延伸：把读取按卡片统一。
- **系统提示保留一份很小的 tab 清单**（建议）：只有卡片引用、类型、身份、可用状态和可作为哪些工具的目标，不含内容；它由今天的 `<host_session_facts>` 泛化而来，不增加外发，让模型知道有哪些卡片、何时该调用工具。
- **审批**：只读，与现有只读查询一致，不弹审批。
- **隐私**：只在模型调用时发送卡片内容，比"每轮推送"少；与生产现状相比不增加外发。上下文提供者只返回文本，看画面仍走 bmc 的 `screenshot` 工具及其审批。
- **token 与延迟**：需要内容时多一次工具往返；不需要内容的问题完全不花上下文 token。
- **模型不调用的风险**：执行规则加调用引导，tab 清单提示有内容可取，用户附加的选区照旧直接进消息；不建议默认"首轮自动调用"，评估后若漏调用明显，再做成可关闭的设置另行决定。
- **衔接**：`CardAi.summary` 是 `host.tab_context` 的数据源，`CardAi.tools` 引用统一注册表里的细节工具；插件卡片声明 `ai` 须有 `ai_integration` 权限。
- **与现有工具分工**：`host.read_terminal` / `host.search_terminal` 负责单会话精确读取，`host.get_current_context` 负责绑定与权限元数据，均保留；legacy `read_terminal` 另行评估退役。
- **测试**：推送文本的 golden 测试作废，改为 `host.tab_context` 返回结构与 tab 清单的 golden 测试；新增一条 e2e；断言请求工具列表或系统提示片段的 AI e2e 逐个核对。
- **用户确认**（2026-11-13）：系统提示里保留只含元数据的 tab 清单；不默认首轮自动调用。
- **用户补充要求**（2026-11-13）：原话"每个AI agent的tool还要支持一些params，比如多少历史的信息，等，每种card type自己内部实现怎么query和组装信息。"据此：
  - （初版，`e9acd990`）曾把这些参数做成 `host.tab_context` 的两层参数与按类型扩展参数，并让 `CardAi` 变成自定义的 `query` 接口。
  - （简化后，见 2.5.8 的"拉取式 tab 上下文"与"简化前后对比"）这些参数落在**各卡片类型自己的工具**上：终端的历史范围、搜索、游标续取就是现有的 `host.read_terminal` / `host.search_terminal`；文件、BMC 各用自己的工具，有缺口在那些工具上补。`host.tab_context` 只做概览，参数只有 `card_refs` 与 `max_bytes`。"每种卡片类型自己实现取数与组装"落在"摘要函数 + 自己的细节工具"上。所有工具都是固定 schema，不支持的参数由 `additionalProperties: false` 直接报错。
  - （ai-followup 包，2026-11-13）用户在下一个包的任务里再次给出同一句原话，并明确要求 `host.tab_context` 本身支持保留参数 `max_lines`、`limit`、`cursor` / `next_cursor`，每种卡片类型在自己的 `CardAi` 里声明并实现，不支持的参数由统一流水线返回结构化错误与提示。据此在简化版之上补回**按卡片类型声明的查询参数**（落地见 2.5.8"`host.tab_context`（概览）"的"查询参数"小节）；细节工具的分工不变。与初版的区别：不做 `type_params` 扩展参数、不按 tab 生成 schema（schema 仍固定，只多三个保留参数），游标不签名、只用于分页卡片自己的内存快照。
- **用户澄清**（2026-11-13）：一方内部按"写 agent tool"的方式与各非 AI 部分沟通，不用 MCP、不加协议层；但要有统一的调用流程、接口与 schema。据此新增 2.9"统一工具接口"：统一 `ToolDef`、统一调用流水线（解析 → schema 校验 → 作用域与权限 → 审批 → 分发 → 结果规范化 → 脱敏与截断 → 审计 / 执行记录 → 返回）、统一注册表、统一 schema 约定（注册期强制，复用现有校验器并写明局限），并能一对一导出为 MCP tool。现有三条注册路径分 T1–T3 收敛；M11 建立在 T1、T2 之上。2.5.8 与 M11 删掉了上一版的过度设计（见 2.5.8 的"简化前后对比"与 2.9 第 6 条）。
- **阶段**：单独一个包 M11，紧跟 4c′ 的 M10（依赖 tab owner；M10 行为不变，M11 是用户可见的 AI 行为变化，分开评估与回滚）。

**第九批判定（2026-11-13）：浮动卡片切换 tab 时的动画可在设置里选**

用户原话："可以的，你可以在settings里设置，一个是带缩放回anchor的退场动画，另一款是直接fade out，带一点缩小一点点"

- **新增设置项** `ui.float_card_transition`，两种：`anchor`（用 Z12 的 `AnchorTransition` 缩放并沿曲线收回到所属 tab，切回时从 tab 位置展开）与 `fade`（原地淡出加轻微缩小，入场反向）。**默认 `anchor`**（建议：最贴合"浮动卡片属于所属 tab"的判定，且 Z12 第一级已实现）。
- **"减少动态效果"优先级最高**：开启时两种都退化为 zenit 默认的原地淡入淡出（或按 token 直接显隐）。
- **适用范围**：浮动卡片（会话记录、AI 面板）切换 tab 时的退场与入场，以及 `ai.launcher` 展开成 AI 面板、面板收起回图标的过渡，都遵守同一个设置。
- **位置与控件**：设置 › 外观与主题 › 终端与工作区，一行"浮动卡片切换动画"，zenit 原生 `W.RadioGroup`。test_id `settings.field.float_card_transition`，选项 `.anchor` / `.fade`。
- **配置与兼容**：`config.zig` 的 `Ui` 增加 `float_card_transition: FloatCardTransition = .anchor`，按常规写出。兼容依赖 config-unknown-keys（已合入）：未知键和未知段跳过并告警、按原文往返保留，含该修复的版本读到这个键会跳过并保留，保存后也不会丢。
- **zenit 侧**：Z12 第一级已在上游完成（`feat/app-extension-points` @ `db1fdd26`，`docs/ANCHOR_TRANSITION.md`；Yix 属性 `motionAnchor` / `anchorCollapsed` / `anchorTo` / `anchorRect` / `anchorMotion`，Zig 为 `ui.fx.AnchorTransition`；token 收回 0.28s、展开 0.32s、`ease_in_out_cubic`），尚未同步进 ZeroWork。`fade` 模式需要的"原地淡出加轻微缩小"没有现成预设，登记上游小项 **Z12b**（`anchorMotion` 增加原地 `fade_scale` 模式，缩放比例作为新 token），不在下游手写；Z12b 之前 `fade` 先按纯淡入淡出执行。第二级 genie 暂不做。
- 落到本文：2.5.7（"切换 tab 时的退场与入场动画""设置项的落点"）、2.5.8 的"入口 › 过渡"、PL4b（退出标准与 e2e）、4c′（接入动效）；`docs/ui-revamp/ARCHITECTURE_PLAN.md` 3.5 的 Z12 行与新增的 Z12b 行。

**第十批判定（2026-11-14）：会话卡片可以浮动，AI 可以放进分屏**

用户原话："ssh类的也是可以floating的啊，AI chat也是可以放回cards layout的。"

- 终端（本地 / SSH）、文件（SFTP）、KVM 以及注册表里所有会话类卡片：在标签页、分屏之外**也可以浮动**；浮动卡片仍属于原 tab，会话照常运行（同一个内容节点搬动）。
- AI 对话：浮动之外**也可以放进 tab body 的分屏**；**仍不能单独成 tab**（Q4 不变）。本条取代“只保留浮动”判定里关于分屏的部分（AI 仍绑定在 tab 上，M10）。
- 会话记录不变：可作为 tab 打开、可浮动、不能分屏（Q11）。
- 落到本文：2.5.4 的放置表与“AI 对话”一节、2.5.7 的“会话卡片浮动 · AI 放进分屏（cards-float）”。

**仍开放、执行到相应阶段再定的事项**

1. （已由第六批判定消解）AI 附着的两处门禁读法不一致。
2. （已定稿，2026-11-13）`ai.launcher` 与 Q5 开关行的设计稿：XqqLV 区域，节点见 2.5.8 的"入口"与 6.2.1 Q5 的"界面"。
3. （已判定，见下方第五批）Q20、Q21。
4. **Z12 的同步与 Z12b**：Z12 第一级已在 zenit 上游完成（`db1fdd26`），待同步进 `vendor/zenit`；`fade` 模式需要的原地"淡出加轻微缩小"预设 Z12b 待上游补；第二级 genie 暂不做。
5. **Z13 的排期**：设计系统 Card Type 组件的禁用样式；不阻塞 PL2（向导用下拉的禁用选项）。

### 6.3 备选方案与不选的理由

**A1 用清单的 `status: planned` 字段表示计划中。**
不选。计划中的协议没有代码，这份清单只能由宿主代写，本身就是编造；它会进入注册表快照，每个消费者（协议选择器、会话宿主、工具目录、侧栏）都得记得过滤，漏一处就出现"可选但必然失败"的入口；它还会诱使人给计划项填能力。独立类型把这三个问题都挡在类型系统外。

**A2 一切皆插件（终端、历史、AI、设置都改成插件）。**
不选。它们与 core 深度耦合，改成插件就得让它们 import core，"插件只能碰 `plugin_api`"的规则对它们全部失效，信任分级变成空话；同时要推翻正在进行的 feature 分层。用户可见的收益为零。本方案用"同一套贡献类型"取得了同样的表达力。

**A3 由插件作者手写能力列表（清单里一个字符串数组）。**
不选。这就是"编造"的制度化：列表与实现之间没有任何机器校验，迟早漂移（1.5 的计划表、1.8 里设计稿对 SSH 文件能力的误判都是现成的例子）。

**A4 能力列表由宿主为每个插件维护一张表。**
不选。这是 `description()` / `permissions()` 按 ID 分支的放大版，违反 V0.2 §8.0.2，新增插件必须改宿主。

**A5 运行期加载动态库 / 内嵌脚本引擎 / WASM 沙箱。**
不选，理由见 4.5。补充两点：WASM 能隔离计算，但插件 UI 必须是 Yix 原生视图，WASM 插件拿不到；脚本引擎引入一个新的运行时和新的攻击面，与"不引入新的脚本运行时"的既有取向相反。

**A6 通用事件总线（插件可订阅任意应用事件）。**
不选。总线让依赖关系从 import 图里消失，check-arch 看不见；事件载荷容易夹带跨 owner 的数据。现有的类型化通道（会话事件、通知、能力 revision）已经够用，缺什么就加一条类型化通道。

**A7 不设 `plugin_api` 层，插件按 feature 规则直接 import core。**
不选。那样 T0 与 T1 没有区别，权限声明没有落实手段，API 面无法审阅。代价（bmc 的 import 要改道）是一次性的。

**A8 直接升到 API 3，重写清单。**
不选。没有必须破坏兼容的改动；V0.4、V0.5 的设计都建立在 API 2 上。

**A9 先把现有命令式的"协议插件"面板原样 Yix 化，再谈能力。**
可行但不推荐，见 Q2。

**A11 另建一套通用的 dock / split 布局引擎，把 tab、分屏、浮动统一成一棵布局树。**
不选。现有的 `group_layout` 二叉分屏树、组 tab、拖拽入组、比例持久化已经覆盖了"一个 tab 装多张卡片"，并且有测试和 e2e；浮动今天只有 AI 面板和会话记录两个使用者，停靠已判定删除。重写布局引擎的回归面远大于把叶子从会话泛化为卡片。

**A10 内容放置支持独立的系统窗口（把内容拖出成新窗口）。**
本方案不含。三种放置是独立 tab、分屏、浮动；现有的跨窗口移交（`supports_window_transfer`）保留；"浮动"指同窗口内的浮层，与 AI 面板今天的浮动一致。独立窗口是另一项工作。

### 6.4 关联风险 / 后续独立项

不属于插件化范围，但在本轮调研或 GLM 评审中发现、与本方案的论据或安全模型相关的事项。这里只登记，不排进 PL 阶段。

| # | 事项 | 事实 | 与本方案的关系 | 建议 |
|---|---|---|---|---|
| X-1 | **打包没有启用 hardened runtime** | `scripts/package_macos.sh:74`（`ZeroWorkUpdater`）、`:76`（`Contents/MacOS/zw_*`）、`:78`（主 App）三处 `codesign --force --sign` 都没有 `--options runtime`；仓库里没有 ZeroWork 自己的 `.entitlements` 文件（唯一的几个在 `vendor/libghostty-vt/macos/`，与打包无关），`scripts/macos_signing.py` 也没有相关设置。GLM 发现，已复核 | 4.5 第 4 条"签名会挡住运行期加载"的论据今天不成立（已在 4.5 更正）；与插件的编译期链接没有直接关系 | **已登记，暂缓**（Q18：用户这次未选，暂不立项）。将来立项时需要评估：现有功能是否依赖 hardened runtime 默认禁止的能力（例如 JIT、未签名可执行内存、`DYLD_*` 环境变量、加载其他团队签名的库），需要哪些 entitlements；按 AGENTS.md 的流程验证 DMG 与自动更新 ZIP 的签名；公证（notarization）是否一并处理。不在插件化的任何阶段里顺手做 |
| X-2 | **高风险解析器仍在主进程内** | bmc 的 RFB、JPEG（`platform/jpeg.c`）、zlib（`protocol/zlib_shim.c`）、TLS（`protocol/tls_shim.c` + mbedtls）、Redfish JSON 都在主进程里解析不可信的远端数据；钥匙串 vault 也在同一进程（V0.2 §4.2.2）。GLM 建议提前 | 4.1 把它列为最现实的高危；本方案的权限与 lint 对它无效 | **已立项（Q17 已判定）**：与 V0.5 并行，不并入 PL 各阶段；它涉及帧数据跨进程传输的性能与复杂度，需要单独的设计文档（先写设计文档，再排期实现）。在它完成之前的缓解是 Q5 的禁用开关（不用就关掉）与解析器模糊测试 |
| X-3 | **MCP 子进程是新的运行期代码面** | `src/ai/mcp_native.c` 编进 `core`（`build.zig:65`），由应用启动第三方 MCP 服务器进程 | Q8 的硬性规则只管进程内；MCP 在进程外，但不等于已隔离（4.5） | 由 V0.4 的设计负责它的威胁模型（启动命令来源、环境变量与凭据传递、工具审批）；本方案只在 4.5 写明边界 |

### 6.5 GLM 交叉评审的处理

GLM 评审的是较早的版本 `40480549`，之后本文已按用户判定改写了 2.5（内容卡片模型）、PL4b、PL4c 等，所以部分意见针对的是已被取代的表述。GLM 给出的 `文件:行号` 都回到代码里复核过；与它的结论不同的地方，在"理由"里写明。

**B 节：问题清单**

| # | GLM 的意见 | 处理 | 理由与落点 |
|---|---|---|---|
| B-1 | `no-plugin-id-branch` 现有 check-arch 表达不了 | **接受** | 复核属实，并且范围比 GLM 说的更大：`findSequence` 只匹配标识符，字符串字面量、`extern`、`@cImport` 都匹配不到。改为两步：标识符部分立即上线；字符串部分加 `forbid_strings` + `allow_files` 的工具扩展，随 PL3 第 8 步（3.3） |
| B-2 | 权限词表没覆盖"AI 提示注入 → 插件工具" | **接受（扩大）** | 新增权限 `ai_integration`，覆盖工具和 `ai_context` 摘要（摘要也会发给 AI 服务商）；`publish` 校验（2.2 第 4 条、4.3）。补充事实：工具目录枚举时还要求 `integration.ai`（`ai_tools.zig:328`），但这是插件自填的标志，不是权限 |
| B-3 | `ContentOwner` 新变体破坏判等 | **部分接受** | GLM 针对的是旧版的 `standalone: ContentId`；现在是 `card: CardId`。把 `CardId` 定成 `{ slot, generation }`，代次在值里，`std.meta.eql` 逐字段比较就正确，不需要改写 `eql`；补一条单测（2.5.3）。另外，GLM 说 `HistoryId` 是"持久实体 ID"，复核不成立：它在每次打开时运行期分配（`workspace.zig:5653`） |
| B-4 | 卡片 vtable 弱于 `RendererInstance` | **接受** | 加 `update(CardUpdate)`，保留 `connection_status`、`show_connection_details`；写明 `mount` / `unmount` 配对规则；窗口移交判定改读 `card_type` 并有等价单测（2.5.3、PL4a） |
| B-5 | 会话记录的 browser / replay 都标 standalone，与现状冲突 | **驳回（已被用户判定覆盖）**，补一句过渡说明 | 用户已判定会话记录是一张 `history` 卡片（6.2.1），不再拆成两种内容。补充了 H1–H4 期间旧归档 tab 仍是 `.history` owner 的过渡说明（2.5.4） |
| B-6 | `plugin-raw-io` 禁用清单有错、覆盖不全，C 链接不在源码层 | **部分接受** | 补上 `std.c`、`std.Io.Dir`、`std.Io.File`、`std.DynLib`、`@extern`；例外按权限分；加"`build.zig` 的插件 C 源与清单 `native_code` 一致"的校验（3.3）。不接受的两点：`std.Io.net` 真实存在（全仓 11 个文件），保留；`@embedFile` 是编译期嵌入，不是运行期 IO，不禁 |
| B-7 | `no-plugin-import` 依赖的跨 feature 机制对 core 与插件目标不触发 | **接受** | 复核属实，且发现更严重的一点：插件与 features 共用 `facade / model / view / host` 层名，features import 插件门面今天两种机制都拦不住。改为插件目录用独立层名，`no-plugin-import` 落成纯矩阵规则，退出标准按新规则名写（3.3、PL3） |
| B-8 | PL1 的 e2e 退出标准部分无依据，文件归属有误 | **接受** | `settings.plugin.ssh.version.message` 在 `plugin_settings_v3_native.ts:33`，已更正；PL1 退出标准按实际断言改写 |
| B-9 | `plugin_ui_contract` 搬家能清掉两条 `layer:view->core`，基线里查不到 | **驳回** | 基线里有：`tools/arch/baseline.txt:843`（`wizard.zig`）、`:978`（`workspace.zig`）。GLM 只看了 `view->legacy_plugin` 那一段（3.1 已注明） |
| B-10 | "100 条涉及 `plugins/`"口径不明，GLM 数到 89 | **部分接受** | 数字不改：`grep -c 'plugins/' tools/arch/baseline.txt` 的结果就是 100。接受"写明口径"，已在 1.7(e) 注明 |
| B-11 | PL1 退出标准自相矛盾（逐像素一致 vs 权限文案改由词表生成） | **接受** | 改为"权限文案等价并经用户认可、含'声明性约束'一句；其余逐像素一致"；`plugin_settings_v3_native.ts:36`、`:41` 的权限弹窗截图在同一提交里更新（PL1） |
| B-12 | PL4b、PL4c′、PL5 挤在波次 C 前后，缺先后 | **接受** | 5.1 新增硬约束 4：M1–M6 可在波次 C 之前做；M7（浮动层）在波次 C 的 `Workspace` 拆分之后；H3–H5、4c′ 随之在后 |
| B-13 | PL4a 不必排在 PL3 之后 | **部分接受** | M1–M6 可与 PL3 并行（5.1 硬约束 5）；`CardViewDef` 先放在 `host/plugin_ui_contract.zig`，由 PL3 搬到 `plugin_api/ui.zig`。M7 仍受 B-12 的约束 |
| B-14 | `native_code` 等于没有边界，应写成显式条款 | **接受** | 4.3 新增显式条款，并补充事实：`addBmcNative` 挂在 `core` 模块上（`build.zig:72`） |
| B-15 | 内置级插件形成"双 API 面" | **部分接受** | 承认三个内置插件的 API 面就是 core；不要求它们立即只经 `plugin_api`（它们本来就是 core 引擎的适配器），而是让它们到 core 的 import 进基线、只降不升，新代码能走 `plugin_api` 的必须走（3.2） |

**C 节：补充意见**

| 意见 | 处理 | 理由与落点 |
|---|---|---|
| 能力谓词"附着 AI 助手"应是 `integration.ai or ai_context != null` | **接受** | `Evidence` 加 `any_of` 与 `ai_context`（2.3）；同时发现 `ai_session_context.zig:8` 只读 `integration.ai`，两处门禁不一致。之后用户判定 AI 能力只在卡片类型上配置（6.2.1 第六批），PL1 先收敛到同一个谓词，PL4a 改为从卡片派生，这个不一致随之消解 |
| 路线条目冲突校验要放在包含全部生产清单的测试根 | **接受** | 2.2 第 6 条 |
| 加 `ident:no-dylib`，让 Q8 可机检 | **接受** | 3.3；今天全仓零命中 |
| Q8 的措辞要覆盖 MCP | **接受** | 4.5 给出完整措辞；MCP 的威胁模型归 V0.4（6.4 的 X-3） |
| "声明性约束，非授权门禁"作为 PL1 退出标准 | **接受** | 4.3"展示"、PL1 退出标准 |
| Q5 不应拖到 PL6 | **接受**（用户已判定） | 6.2.1 的 Q5 |
| 卡片类型 `register` 的调用时序 | **接受** | 2.5.3"登记时序"：只在组合根、首个窗口之前、两阶段一次性发布 |
| history 嵌 terminal 回放表面，terminal 门面需冻结并有退出标准 | **接受** | PL4b 的 H2 加契约单测作为退出标准 |
| PL6"只改插件目录"与 `native_code` 插件必改 `build.zig` 矛盾 | **接受** | PL6 加显式豁免，`build.zig` 的改动按基础设施变更评审 |
| `host_api_minor` 要写清哪些 core 类型算 API 面 | **接受** | 3.1：从 `plugin_api` 两个文件可达的公开声明都算，用快照单测落实 |
| 把高风险解析器提前移到进程外 | **部分接受** | 接受"不能写成'有证据后再说'"，登记为独立项 X-2（Q17），建议与 V0.5 并行；不并入 PL 阶段，因为它需要自己的设计（帧数据跨进程的性能与复杂度） |
| "新增插件 C 源属于基础设施变更"写进审计 checklist | **接受** | 4.3 的审计 checklist；写进 `AGENTS.md` 暂缓（Q19），内容先留在本文 |
| PL3 硬退出项"`features/ai` 不 import 插件内部" | **接受** | PL3 退出标准；复核后区分了非测试（`ai_host_queries.zig:10-11`）与测试（`ai_tools.zig`、`ai_lifecycle_controller.zig`）的 import，测试也一并清零 |
| `Icons` 有默认值，清单不填图标也能过长度校验 | **记录** | 只有在能力目录新增图标类证据时才需要收紧；目前没有这种证据，不改 |

**D 节**：Q1–Q10 的意见与本文建议一致，Q5 的"有条件同意"已由用户判定采纳。

**E 节**：6 项核实结果已写回第 7 节并标为"已核实"。其中 (i) 的结论修正了 1.7(a)；(ii) 修正了 4.5 第 4 条并登记 X-1；(iii) 写入 2.3 的准入规则；(iv) 写入 PL1；(v) 写入 PL3 第 7 步；(vi) 写入 2.3 的补充候选表。

**F 节**：10 条抽查中 F-9（`pane_manager` 的活跃度）**接受并修正**：它只被测试引用，不在运行期路径上；但 GLM 说 `group_dispatch.zig` 没有这条 import 不对，该文件在 `features/workspace/model/` 下，第 8 行就 import 了 `pane_manager`（2.5.2 末尾、Q16）。其余 9 条属实，无需改动。


---

## 7. 附录：证据索引

| 主题 | 文件 |
|---|---|
| 清单、注册表、校验 | `src/host/plugin_registry.zig`（`PluginManifest` `:117-150`；`publish` `:226-365`；`Origin` `:67`；legacy 枚举 `:6-35`） |
| UI 契约 | `src/host/plugin_ui_contract.zig`（`EditorMount` `:28`、`ContentMount` `:78`、`RendererDefinition` `:113`） |
| 宿主上下文与安全宿主 | `src/host/host_context.zig`、`src/host/plugin_security_host.zig` |
| 能力投影 | `src/host/capability_snapshot.zig`、`src/host/actions.zig:62` |
| 组合根 | `src/plugins/linked_plugins.zig`、`src/plugins/application_plugins.zig`、`src/app/main.zig:87-92`、`src/host/session_host.zig:363` |
| 插件清单实例 | `src/plugins/bmc_ikvm/plugin.zig:105-131`、`src/plugins/fixture_probe/plugin.zig:206-227` |
| 设置页 | `src/features/settings/view/panes/settings_plugins.zig`、`src/config/plugin_page.zig` |
| tab 与内容 | `src/host/identity.zig:82-86`、`src/features/workspace/view/workspace.zig:107-145`、`:5252`、`:5630`、`src/features/shell/host/plugin_content_host.zig` |
| 分组与分屏 | `src/features/workspace/model/{group_layout,group_model,workspace_model,pane_manager}.zig`；`workspace.zig:2179-2185`（`canGroupTarget`）、`:3261`、`:3367` |
| 会话记录与 AI 面板 | `src/features/history/host/history_host.zig:66-70`、`src/features/ai/pane/view/ai_pane_layout.zig:20`、`src/features/ai/host/ai_host.zig:3784` |
| AI 工具 | `src/ai/plugin_tools.zig:9-48` |
| check-arch | `tools/arch/rules.zon:66-82`、`:95-166`；`tools/arch/baseline.txt`（1,033 条，其中 100 条涉及 `plugins/`）；`tools/arch/README.md` |
| 构建 | `build.zig:23-24`、`:212`、`:833-834` |
| e2e | `e2e/plugin_settings_v3_native.ts`、`e2e/v02_plugins_ui.ts`、`e2e/v02_fixture_native.ts`、`e2e/bmc_*`、`e2e/kvm_*` |
| 设计稿 | Pencil 节点 T5k96（协议插件列表）、KUKQ5（SSH 单协议页）、ibeKI（能力对照）；本轮读的是导出 PNG，没有通过 Pencil MCP 读数值 |

**已核实的事项**（GLM 评审 E 节的 6 项与 F-9，均回到代码复核过）

1. **已核实**：`src/ai/{image_offload,plugin_tools,tool_results}.zig` 对 bmc 的 6 处 import 全部在测试块内（`image_offload.zig:389`、`:434`、`:440`；`plugin_tools.zig:892`；`tool_results.zig:482`、`:489`）。它们仍计入基线的 `layer:core->legacy_plugin`（`baseline.txt:652-657`），清零手段是把这些测试挪到 bmc 的 `tests/`。`src/ai` 的非测试代码对 bmc 只有字符串匹配，没有 import。
2. **已核实**：打包没有启用 hardened runtime（`scripts/package_macos.sh:74`、`:76`、`:78` 无 `--options runtime`、无 `--entitlements`）。见 4.5 第 4 条与 6.4 的 X-1。
3. **已核实**：`actions.zig:70-71` 的 `groups`、`recording` 没有清单层来源；在 `serviceCapability`（`:266-270`）里被当作服务能力，有快照时跳过、无快照时回落到 `context.supported`（`:295-298`）。"输入广播""会话录制"暂不进能力目录（2.3）。
4. **已核实**：e2e 没有断言权限弹窗的原句，但 `plugin_settings_v3_native.ts:36`、`:41` 截了权限弹窗；单测 `src/features/settings/tests/plugin_settings_v3_tests.zig:65` 断言了原句"连接时按需请求权限"，`:64` 断言说明回落为 `workspace_kind`。PL1 同步改写（5.2 的 PL1）。
5. **已核实**：`session_icon.zig:98` 的回退改读清单**不会**逐像素不变，需要在 `Icons` 里加专门字段（5.2 的 PL3 第 7 步）。
6. **已核实**：能力目录候选漏了 `process`、`auth`、`auxiliary_readonly`、`auxiliary_transfer`、`directory_recovery`，已补进 2.3 的补充候选表；`temporary_connection`、`probe` 两项证据成立（`plugin_registry.zig:90`、`:97`）。
7. **已核实**：`pane_manager.zig` 只被测试引用（经 `shortcut_dispatch.zig:3`、`group_dispatch.zig:8`，二者都只在 `src/root.zig` 以 `_ =` 拉进测试），不是运行期路径（2.5.2 末尾、Q16）。

**本轮没有核实、需要执行者确认的事项**

1. `remote/editor.zig:44` 的 `Protocol` 枚举里 8 个未实现成员的全部使用点，以及已保存配置里是否可能出现这些协议值（6.2.1 的附带建议）。**已核实并落地（plugin-truth 包）**：枚举从不持久化——`hosts.toml` 的协议由 `config/hosts.zig` 解析，`ssh` / `sftp` 之外的值原样存为 `protocol_id`，走"未知插件可列出、不可连接"；编辑器只从插件 ID（`editor_factory.zig`，本来就拒绝 ssh / sftp 以外）和选择框（只有两项）取值；e2e 与测试没有使用这 8 个成员。因此提前删除，`hosts.zig` 新增单测断言这 8 个值的旧配置照常加载并原样回写。
2. PL4c 相关：`toggle_ai` 的默认按键与 macOS 菜单栏是否有对应项；`ai.launcher` 的 KVM 帧率浮层矩形如何从 bmc 卡片取得、位置是否跨重启保留（按 wqZ1s 核对）；空工作区时今天是否能打开 AI；AI 条删除后默认浮动矩形的确切数值；哪些 e2e 断言了 AI 停靠布局的几何；`ai_float_geometry_native.ts` 今天如何在默认停靠下进入浮动形态；浮动卡片的位置与尺寸是否持久化；从停靠切到浮动时初始尺寸的来源。
3. PL4b 相关：是否存在已打开归档 tab 的持久化（grep 未发现）；`SessionTab.archived` 的全部使用点；候选 e2e 清单里哪些真的依赖归档 tab。
4. 能力目录的最终条目与每份清单的求值结果（PL1 的产出，本文 2.3 的表只是基于已读代码的候选）。
5. （已由第六批判定消解，见 2.5.8）AI 附着的两处门禁读法不一致。执行时仍需核对：会话离开组时对话今天的确切去向（4c′ 保持）；旧版本读到 schema 4 的会话日志行时，是只丢 AI 历史还是影响启动。
6. Q5：侧栏是否已有通用的"不可用原因"节点可以复用；提前读取 `host.enabled` 采用哪种方式（6.2.1 的 Q5"配置"）。
7. Q16 的删除包：`pane_manager` 等三个文件的测试是否覆盖了运行期实现没有覆盖的行为（有就改挂，见 5.2 的 PL4a）。
8. 浮动（2.5.7）：tab 条里每个 tab 节点的 test_id 与全局矩形怎样读到（收回锚点）；状态栏节点的 test_id（`ai_float_geometry_native.ts` 断言卡片压住状态栏时要用）；e2e 工具能否读到卡片根节点上的收回状态；`kvm_ai_layout_native.ts`、`floating_input_native.ts`、`ai_tab_presentation_native.ts` 是否断言了"AI 在所属窗格内"。


