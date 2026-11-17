# 人工验收 · 第 2 轮指南（第一批收尾）

对应集成分支 `feat/ui-arch-revamp` 第一批收尾后的尖端（vendor zenit `feat/app-extension-points` @666ea295）。第 1 轮 11 条反馈的逐条状态、做了什么、修复后截图见 [`round-1.md`](round-1.md) 的“第 2 轮验收材料”一节；截图集中在 `~/work/ZeroWork-evidence/round-2/`（下文简写 `round-2/`），文件名前缀 `light-` / `dark-` 是主题。

每一项请对照截图与真实窗口给出“通过 / 不通过 + 意见”。

## 〇、启动验收版本

验收用 **test-mode 构建**：它只认私有 HOME 和 `ZEROWORK_DATA_DIR`，不读写你的真实配置、会话和 `~/Library`。正式构建（不带 `-Dtest-mode=true`）会写真实的 `~/Library/Application Support/com.zerowork.app`，本轮不要用它验收。

```sh
# 0. 变量（从仓库根目录运行，验收数据放在权限为 0700 的临时目录）
N="${ZW_NONET_WRAPPER:?Set ZW_NONET_WRAPPER to the absolute path of zw-nonet.sh}"     # 断网运行
R=/private/tmp/zw-accept
mkdir -m 700 -p $R $R/home $R/tmp $R/data
export HOME=$R/home CFFIXED_USER_HOME=$R/home TMPDIR=$R/tmp/ ZEROWORK_DATA_DIR=$R/data \
       ZIG_GLOBAL_CACHE_DIR="${ZIG_GLOBAL_CACHE_DIR:-$HOME/.cache/zig}"
unset SSH_AUTH_SOCK
# 关掉自动检查更新（断网下也不会联网，只是避免启动时的失败提示）
printf '[meta]\nconfig_revision=1\n[updates]\nauto_check=false\n' > $R/data/config.toml

# 1. 构建（在仓库根目录，集成分支尖端）
git switch feat/ui-arch-revamp && git log -1 --oneline      # 记下这个 commit
"$N" zig build -Dtest-mode=true -j4 --prefix $R/prefix

# 2. 启动（前台运行；关窗或 ⌘Q 退出）
"$N" $R/prefix/bin/zerowork
```

说明：

- 上面的 `export` 只影响当前终端会话；验收完关掉这个终端即可。test-mode 构建在 HOME 不是私有目录、或 `CFFIXED_USER_HOME` 与 HOME 不一致时会在第一行拒绝启动（`ZeroWork test build refuses to start (...)`），这是保护，不是故障；详见 `docs/ui-revamp/HOME_ISOLATION.md`。
- 这样启动的是裸可执行文件，没有 `.app` 包装：Dock 图标、应用名显示与正式安装包不同，这不在本轮验收范围。
- 想从干净状态重来：退出应用后 `rm -rf /private/tmp/zw-accept`，再从第 0 步开始。
- 主题切换：设置 › 外观与主题 › 主题（截图里的 light / dark 即这里的亮 / 暗主题）。

## 一、第 1 轮的 11 条反馈

| # | 验什么 | 怎么验 | 截图 |
|---|---|---|---|
| 1 | 设置窗口左侧导航浮层、底部 Save Bar 是原生 liquid glass（`W.GlassBox`）；页头后退 / 前进 / 帮助是原生 macOS 工具栏按钮组 | 打开设置，看左侧浮层、页头三颗按钮；进子页后点后退 / 前进 | `round-2/01-glass/` |
| 2 | 开关、单选、复选是 zenit 默认外观（关：浅灰轨道 + 白色滑块；开：靛蓝）；外观页的主题卡片、对齐九宫格、应用图标、光标形状是原生单选 / 分段 | SSH › 断线重连（开 / 关自动重连，看依赖项变灰）；外观与主题各子页 | `round-2/02-controls/` |
| 3 | 页头下的标题栏边缘渐变；**静止时页头下第一行（分组标题与右侧摘要）清晰**；正文滚到页头下方时才出现渐进磨砂 | SSH › 断线重连：不滚动，看“断线重连 / 自动重连与输入缓存”是否清楚；快捷键页往下滚，看滚进页头下的那一行是否被磨砂 | `round-2/03-header/` |
| 4 | 保存逻辑：只看右侧当前子页；有改动才出现 Save Bar；“恢复默认…”只在本页值与默认值不同时可点，先确认；保存成功 / 失败是原生 Toast；带改动切页 / 关窗先确认 | 改一个字段 → 看 Save Bar → 保存看 Toast；再改 → 切页看确认；点“恢复默认…” | `round-2/04-save/` |
| 5 | 右侧内容与导航滚动有原生回弹 | 用触控板在长页面（快捷键）顶部 / 底部继续拖动 | `round-2/05-rubberband/`（静态画面，手感需真机） |
| 6 | 设置行之间有分隔线（设计稿 `w3r3t`），九类面板都有，末行不画 | 逐个分类看 | `round-2/06-dividers/` |
| 7 | 快捷键行：悬停出现编辑提示 → 点击原地录制 → Esc 取消 / Tab 或失焦结束；冲突给“交换 / 取消”；每行可单独恢复默认；键帽是原生 `W.Kbd` | 快捷键页按左列逐项操作 | `round-2/07-keys/` |
| 8 | 对话框是原生 `W.Modal`：半透明遮罩，面板是 zenit 默认外观（不透明、默认圆角 / 描边 / 阴影） | 设置里“恢复默认…”、带改动切页 / 关窗、清除全部数据…；主窗口关闭标签页确认；AI 模型编辑器 / 删除服务提供方 | `round-2/08-modals/` |
| 9 | 设置里的 Input / Select 是 zenit 原生默认外观（有自己的浅色底） | SSH › 连接、文件传输 › 默认行为、AI 辅助 › 服务提供方详情 | `round-2/09-inputs/` |
| 10 | 协议插件：列表页 → 插件详情两级；AI 辅助：服务提供方列表 → 提供方详情两级，行为与权限是普通设置行 | 设置 › 协议插件、AI 辅助 › 服务提供方 | `round-2/10-two-level/` |
| 11 | “?”提示是原生 `W.Tooltip` 默认外观（页头帮助、字段帮助） | 悬停页头“?”与字段旁的“?” | `round-2/11-tooltips/` |

### 第 1 轮留给你确认的设计选择（H-save）

1. 搜索结果页的保存作用域是“全部字段”（就地保存 / 撤销；清空搜索回原页时按原页判定是否确认）。备选：按字段所属子页归属，离开搜索时逐页确认。
2. “服务提供方”页是否保留“恢复默认…”（会清空已配置的提供方，仍是草稿，保存才生效）。备选：该页不显示。
3. Save Bar 在右下角（浮动玻璃胶囊）；保存 Toast 在设置窗口底部居中。备选：Toast 放右上 / 右下。

## 二、第一批里其余要验的改动

| 改动 | 验什么 | 怎么验 | 截图 |
|---|---|---|---|
| 开关首帧与滑动 | 进入有“默认开”开关的页面时，滑块直接停在“开”的位置，不从轨道外滑入；点击时原地平滑滑动 | SSH › 断线重连；外观与主题 › 终端与工作区 | `round-2/extra-switch/`（自动化测试 `switch_initial_state_native` 亮 / 暗都通过） |
| 通知双栈 | 每个窗口两个原生通知栈：**右上角卡片栈**（全局提醒、命令失败提示、操作失败等带动作或需要处理的）；**窗口中下方标准 Toast**（无动作的成功 / 信息：已复制、目录已刷新、保存成功） | 本地终端里执行失败命令（如 `false`）看右上角卡片；选中终端文字复制看中下方 Toast；通知历史弹层；设置里保存看 Toast | `round-2/extra-notify/`（设置保存 Toast / 失败提示；主窗口两栈需真机看） |
| Toast 永远在最上层 | 菜单、弹层或对话框打开时出的 Toast 不被遮挡 | 打开一个下拉 / 对话框的同时触发一条 Toast（如设置里保存） | 无单独截图 |
| 空白窗口修复 | 主窗口启动后侧栏、空工作区、工具栏正常显示且可点击；打开本地终端、打开设置都正常（此前会整窗纯色、点不动） | 正常启动、点“本地终端”、点设置 | `round-2/extra-render/`、`round-2/extra-workspace/` |
| 主按钮外观 | 主按钮（如空工作区“本地终端”、对话框“保存”）的配色。用户已判定 T-1 选 A（统一 zenit 默认），**本批尚未落实**，目前仍是 ZeroWork 主题色，排在 P4 第一个包 | 看主按钮 | `round-2/extra-workspace/default.png`、`round-2/08-modals/` |
| 命令帮助卡改原生 Modal | 有遮罩、默认外观；Esc / 点遮罩 / 关闭按钮都能关，焦点回终端 | 终端里触发命令帮助 | 无（自动化触发不到，证据是组件测试 `command_help_tests.zig`） |
| 自定义 TERM 改原生 Popover + Input | 设置 › SSH › 连接 › 默认终端类型 › “自定义 TERM 声明…”弹出原生 Popover | 同左 | 无单独截图 |
| 背景缩略图 / 行内材质预览 | 外观与主题 › 背景图片：缩略图与行内预览不再空白 | 选一张背景图片（文件选择框是系统面板，需真机） | `round-2/02-controls/`（外观页） |
| 浮层不随材质透明 | 菜单、下拉、Popover 在材质透明度调低时仍不透明 | 外观与主题 › 材质透明度调到很低后打开下拉 | `round-2/extra-opaque/` |
| 配置兼容 | 新版本写过的 `config.toml` 在旧版本里打开不丢未知项；旧配置在新版本里照常读 | 行为项，无需看界面；如要验：把一份旧 `config.toml` 放进 `$R/data/` 后启动 | — |

## 三、已知限制

- **e2e 历史失败**：全量 e2e 回归里约 120 条在批量迁移（第一批）之前就已失败（断言仍按旧界面写、等待的 test id 已改名等），清单见 `ZeroWork-evidence/batch1-gate/triage-dbg.txt`（`known-fail`）。它们与本轮验收项无关，按 P4 / P5 逐包修或改写；本轮新增 / 修好的脚本都已通过（见 `ZeroWork-evidence/batch1-close/`）。
- **ReleaseSafe 的 AI 组 e2e**（清单 `releasesafe` 标签，78 条）第一次在本分支跑：12 通过、66 未通过（等待超时 32、断言 9、其他 13、应用退出 / 崩溃 12，其中 3 次 zerowork 崩溃由 macOS 记了崩溃报告，按规则已删），分类见 `ZeroWork-evidence/batch1-close/regression-rs/TRIAGE.tsv`。这一组此前从未跑过，没有迁移前基线，暂不能区分新旧；抽查到的属于断言过时（如对话框宽度 600 ≠ 500，原生 Modal 默认宽度）。都与 AI 面板相关，不影响本轮 11 条与设置窗口的验收，后续单独分诊。
- **断网环境**：所有构建、测试、验收都在 `zw-nonet.sh` 下断网运行。SSH / SFTP 连接远端主机、AI 服务提供方（真实模型请求）、检查更新都用不了；本轮只验它们的界面（设置页、对话框、空状态）。要验真实连接需另行授权联网。
- **只有真机能验的**：触控板回弹手感（第 5 条）、真实系统文件选择框、系统通知授权、Touch ID / 钥匙串、红绿灯与窗口拖动、输入法。截图来自 Harness 抓取的 Metal 呈现面，不含 macOS 原生红绿灯。
- **通知计时语义**（YIX_EXCEPTIONS N-2 – N-5）：原生栈悬停 / 焦点 / 展开时冻结剩余时间；命令失败提示从终端面板右上角移到窗口通知栈；AI 反馈条关闭按钮是 Alert 外侧单独的原生按钮；通知历史列表高度固定 152–320。均待你判定。
- **设置以外的旧覆盖**：共享的 `styleInput` 等 Input 覆盖、非原生的字段“?”提示还在设置窗口以外的面板里（第 9、11 条“设置以外进行中”），随 P4 / P5 替换。
- **会话记录面板**改 tab content（D-4）是第一批之后的单独包，本轮不验。
- **dark 族组件默认值**与设计稿不完全一致（第 2 条备注），以 zenit 默认为准。
- **设置预览程序**（`settings-preview-runner`，仅开发 / 测试工具）里长页面的内容视口按内容高度布局、不能滚动；真实应用正常。所以 scroll edge 回归测试用真实应用跑。待单独修。
- 测试程序崩溃时 macOS 会在真实 `~/Library/Logs/DiagnosticReports` 写崩溃报告（系统行为，不是应用写入）；e2e 运行器现在只放行我们自己测试二进制在本轮时间窗口内的报告并在结束时删除，其余照旧报警（`e2e/README.md`“崩溃报告”）。

## 构建与环境

- 分支：`feat/ui-arch-revamp`；vendor zenit：`feat/app-extension-points` @666ea295（含 scroll edge 静止不磨砂修复 e804139d）。
- 第一批收尾的验证记录：`ZeroWork-evidence/batch1-close/`（`captures/` 截图采集与设置 e2e、`scroll-edge/` 根因对照、`regression-rs/` ReleaseSafe 组、`cffixed/` 三条补跑脚本）；第一批门禁：`ZeroWork-evidence/batch1-gate/`。
