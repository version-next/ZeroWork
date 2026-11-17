# ZeroWork 原生窗口验证

AI 答复恢复专项：`zig build ai-recovery-preview -Dtest-mode=true -j2` 后运行 `node e2e/ai_answer_recovery_native.ts /tmp/zerowork-answer-recovery`。隔离窗口复用生产恢复卡片，以合成快照检查未知结果、冷却、上下文失败的可见说明、按钮禁用、详情及 600/360 逻辑宽度。命令不重放、未知回执保留、异常工具调用拒绝和归属／预算检查由 `zig build test -Dtest-filter='answer retry' -j2` 验证；卡片预览不代表真实 SSH 已核查。

原调用只读核查：同一 `ai-recovery-preview` 构建后运行 `node e2e/ai_readonly_verification_native.ts /tmp/zw-readonly-verification`，检查原目标、追加证据、旧记录缺少定位信息、原连接失效及 600/360 布局，核查后新计划仍禁用。`zig build test -Dtest-filter='readonly verification' -j2` 和 `zig build test-ui -Dui-test-filter='readonly verification' -j2` 覆盖调用/参数与generation绑定、原SSH快照、零取消/关闭/重放、终端观察不回退到有副作用的snapshot、证据复制及journal重启。预览与受控回执不代替真实服务器业务后果核验。

设置预览 runner：`zig build settings-preview -Dtest-mode=true -j2 --prefix /tmp/zw-set-preview` 后运行 `node e2e/settings_previews.ts --binary /tmp/zw-set-preview/bin/settings-preview-runner --out /tmp/zw-set-preview-evidence`，5 种保留的规划选择分别在 `--layout=content`（只挂内容区，636×628）与 `--layout=window`（完整设置窗口，走生产 aux 窗口路径，960×780）下打开协议插件页，规划投影不得渲染、设置不得变脏。`node e2e/settings_preview_windows_native.ts --binary … --out … [--label yix|legacy] [--parts plugins,selfcheck,geometry,v6]` 在完整窗口上跑 runner 自检（`--self-check=v7` 多窗口 scope 隔离与回收、`--self-check=v11` window chrome 的拖动命中）、设置窗口框架的节点几何（按设计契约）及最小尺寸、切换分类时的焦点／未提交文本／Harness 输入法组合场景，以及 `--plugin-fixture` 只读插件清单。只用内存默认配置和隔离 HOME／RPC 目录，后台窗口，不读写用户数据；真实拖动、红绿灯、双击标题栏和系统输入法不在 Harness 覆盖范围内，手工步骤见 `docs/ui-revamp/YIX_SPIKE.md`「P3 实证」。


使用仓库实际依赖的 Zenit Harness 和本机 Node 26，无需安装服务或 npm 依赖。

真实窗口渲染冒烟（空白窗口回归，43c46538）：`zig build -Dtest-mode=true -p /tmp/zw-smoke` 后运行 `node e2e/window_render_smoke_native.ts /tmp/zw-smoke/bin/zerowork /tmp/zw-smoke-evidence [light|dark|both]`。每个主题用权限 0700 的隔离 HOME／CFFIXED_USER_HOME／TMPDIR／ZEROWORK_DATA_DIR，关闭更新检查：主窗口侧栏、空工作区、工具栏可查询且可见，点“本地终端”出现页签与终端（窗口能接收点击），点设置打开设置窗口（面板、导航、标题）；三张截图都按像素方差（≥ 20）和颜色数（≥ 64）拒绝纯色画面（健康窗口方差约 250–600，空白窗口为 0）。节点树里有内容但画面是纯色、或窗口吃掉全部点击，单测和 compile-tests 都发现不了，只有这类真实窗口检查能拦住。

面板契约（overlay-focus，CONSISTENCY_AUDIT #1）：test-mode 构建后运行 `node e2e/panel_contract_native.ts <zerowork> <证据目录> [light|dark]`（设 `ZW_TEST_PYTHON` 为带 paramiko 的解释器时加跑 SSH 才有的面板，用 `e2e/builtin_records_ssh_peer.py` 的 loopback 夹具）。对标题栏各弹层（提醒、传输、命令历史含 ⇧⌘B 打开、通信链路、端口转发）、新建会话菜单、页签 / 终端 / 侧栏右键菜单、浮动卡片（会话记录、AI）、本地 / SSH 关闭确认框、会话记录卡片里的删除确认、设置窗口的未保存确认跑同一套断言：打开后焦点在面板里（确认框落在“取消”且不弹提示）、Tab / Shift+Tab 不离开面板、Esc 只关最上一层并把焦点还给触发按钮（快捷键 / 右键打开的回到原来的位置）、点外部关闭且焦点留在被点的地方；浮动卡片点外部不关，焦点不在卡片里时 Esc 不关；设置输入框改两次再按 Esc 回到聚焦时的值。报告 `report-<variant>.json` 逐项记录，失败汇总在 `failures`。

终端右键菜单（design-r3 B1）：test-mode 构建后运行 `node e2e/terminal_right_click_native.ts <zerowork> <证据目录> [light|dark|both] [--ssh=<ready.json>]`。本地终端（及 `--ssh` 指向的 loopback 夹具，如 `e2e/ssh_nested_shell_peer.py --nested-ssh` 的 `{port,user,key}`）右键在指针处弹出 `terminal.menu`，核对 粘贴 / 查找… / 复制（未选中内容）/ 清屏 的顺序与有选区时“复制”排第一，并截图；点“粘贴”后回车，确认剪贴板命令真的在该终端执行（写标记文件）；再到设置 › 终端与工作区 › 右键行为 选“直接粘贴”并保存，右键不再弹菜单、直接粘贴。使用系统剪贴板，脚本结束时恢复原文本。

浮动卡片切换动画（Z12b）：test-mode 构建后运行 `node e2e/float_card_transition_settings_native.ts <zerowork> <证据目录> [light|dark|both]`。设置 › 外观与主题 › 终端与工作区 ›“浮动卡片切换动画”（原生 `W.RadioGroup`，`settings.field.float_card_transition`，选项 `settings.option.float_card_transition.{anchor,fade}`）默认“收向所属标签”；选“淡出”保存后 config.toml 写出 `float_card_transition = "fade"`，重新打开设置仍选中“淡出”；截图默认与淡出两态。

KVM 窄分屏工具栏：`zig build bmc-kvm-preview -Dtest-mode=true -j2 --prefix /tmp/zw-kvm-toolbar-build` 后运行 `node e2e/kvm_toolbar_native.ts /tmp/zw-kvm-toolbar-build/bin/bmc-kvm-preview /tmp/zw-kvm-toolbar-evidence`。独立窗口复用生产 renderer，在宽窗口内分别分配 520、336、280、240 点会话宽度，检查图文→五项纯图标→三点收纳、连接状态图标及提示、所有直接入口、菜单边界、键盘进入与回焦、外部点击和拉宽恢复；覆盖晴霜与深色主题并保存原生截图。使用本地合成视频与类型化服务，不连接真实 BMC、不执行电源或启动写入。布局与输入回归使用 `zig build test -Dtest-filter='BMC view' -j2`。

```sh
zig build -Dtest-mode=true -De2e-port=19818 -j2
node e2e/workspace.ts --out /absolute/path/to/evidence
```

文字操作按钮与主题专项：`./scripts/test_isolated.sh test-ui -Dui-test-filter='button policy' -j2` 遍历当前全部内置主题，检查保留节点的次按钮底色／文字、悬停／按下／无描边焦点、禁用门禁及复制反馈恢复颜色。`zig build button-policy-preview -Dtest-mode=true -j2 --prefix /tmp/zw-button-policy` 后运行 `node e2e/button_policy_native.ts /tmp/zw-button-policy /tmp/zw-button-policy-evidence`，在独立原生窗口复用生产远程提示条、AI 恢复卡片、复制反馈和执行／传输／通知的真实样式；遍历主题，并保存代表主题的常规／最小窗口和交互状态。回执为合成数据，不访问钥匙串、真实服务器或模型，不作为主程序启动或真实会话操作的端到端证据。

本地终端原页签重连：`node e2e/local_reconnect_native.ts /absolute/build-prefix /tmp/zerowork-local-reconnect-evidence`。使用隔离数据和真实 zsh PTY，验证 Ctrl+D／非零退出后的“重新连接”、原页签复用、自动回焦、连续重连、860×480 布局及关闭后的进程释放；保存原生截图和报告，最后正常退出应用。

普通 `zig build` 的 `test-mode` 默认为 `false`，发行构建保留该默认值。
`e2e-port` 仅定义默认文件 RPC 目录后缀。Runner 每次创建独立 RPC、应用数据目录和进程，使用它刚启动的 PID，不复用正在运行的用户窗口。

默认步骤捕获 1440×900、860×480 两种逻辑尺寸，并请求 640×360 后断言实际根节点仍为 860×480。每次 resize 等待真实渲染帧递增再读取布局。应用必须已设置 `WindowConfig.min_width/min_height`，该断言才会通过。

输出目录包含 PNG、对应节点树、`app.log` 和 `harness-report.json`；报告记录可执行文件 SHA-256、实际根尺寸、渲染统计及逐步结果。Runner 的通过只表示所列步骤通过。

可以通过 `--binary /absolute/binary` 指定刚构建的验证程序，通过 `--steps /absolute/steps.json` 提供步骤数组：

```json
[
  { "action": "resize", "width": 1440, "height": 900 },
  { "action": "visible", "test_id": "workspace.shell" },
  { "action": "size", "width": 1440, "height": 900 },
  { "action": "capture", "name": "workspace" }
]
```

交互步骤支持 `click`（`test_id`）、`key`（`name`、可选 `mods` 中的 `cmd/ctrl/alt/shift`）、`type`（`text`），以及 `text`（`test_id`、预期 `text`）断言。控件 ID 以实际节点树为准。截图名称仅含字母、数字、下划线和连字符。

截图来自真实 Metal 呈现表面，不包含 AppKit 原生交通灯；交通灯位置及原生点击行为需补充系统窗口截图和操作验证。合成键盘输入也不能代替真实输入法验收。后台运行不会抢前台，收尾仅终止 Runner 自己启动的进程；这不作为应用正常退出与资源关闭链已通过的证据。

`--fixture-dir /absolute/path` 会将指定本地目录复制进本次隔离数据目录，可提供 `config.toml` 和 `hosts.toml`，不会修改原始 fixture 或用户默认数据。报告不复制 fixture 内容。

App历史自动提示专项：构建最新test-mode二进制后，运行 `node e2e/completion_nested_ssh_native.ts /tmp/zerowork-completion-new-run /absolute/path/to/zerowork`。Runner在隔离本地zsh中定义`ede`别名，经系统SSH连接自建loopback服务及真实zsh PTY，验证`find`自动显示先前命令、→仅发送缺少后缀、Enter与Tab原样提交、Esc抑制、登录密码排除及860×480浮层。仅操作自建进程、配置和目录；截图需查看，不代表物理键盘或IME已验收。

`visible` 会等待节点实际获得可见尺寸；`hidden` 会等待节点消失或不可见，可用于确认页签真实移除。`capture` 等待 300ms 让控件进出动画结束后保存视觉证据；它不替代功能完成断言。

`rect` 可按test_id核对实际全局坐标（x/y/width/height，容差0.5px）。`visible/hidden`检查整条祖先可见链，避免隐藏容器内旧节点误判。

`drag` 支持test_id、to_test_id、edge(before/after)及cancel，cancel会在鼠标松开前发送Esc；`tab_order`通过实际可见坐标核对TabId顺序。`block_config_save`仅操作本次Runner自建data目录，将原config.toml改名保留后创建同名目录，用于触发真实写盘失败，不修改产品保存逻辑或用户默认数据。

页签快捷键专项使用 `node e2e/tab_shortcuts.ts --out /absolute/evidence --fixture-dir /absolute/local-refused-fixture`。Fixture 提供一项已保存的本地拒连连接和短连接超时；Runner 创建十个真实会话页签，核对前九项 Command 序号及逐项切换、无 Command 修饰的下一事件恢复图标、860px 下 overflow 首尾几何与禁用门禁，以及连续 Ctrl+Tab 的完整 MRU 顺序和 Shift 反向。查询只读取页签子树，避免完整终端树超过 Harness 结果上限。

该专项仅用公开 Harness API，后台启动独立 PID/data/RPC。当前 Harness 没有 `key_up`，因此 Command/Control 实际松开、窗口失焦与真实 IME 仍需另外通过 CUA 验证；无修饰的 `key_down` 不能作为实际松开凭据。

`scroll` 通过目标节点中心发送真实Harness滚轮事件（`test_id`、`dy`）；`focused` 核对当前实际焦点的 `test_id`，用于阅读位置与浮层回焦验收。按键名沿Harness公开接口使用小写（例如 `backspace`、`return`），不能把未知名称返回ok当成按键已生效。

`hover` 按 `test_id` 通过公开Harness鼠标移动并等待tooltip延迟，可验证不可用原因和完整标题；不能把它当成原生系统鼠标/输入法验收。

## 按钮与尺寸约束审计

`python3 scripts/audit_ui_constraints.py --out /tmp/ui-constraints.json` 生成生产源码逐点清单，保留固定/参数化/内容/可用空间/上下界表达式，不把固定尺寸自动判错。

`node e2e/button_constraints_native.ts /tmp/ui-button-evidence` 使用当前test-mode二进制，在1440×900及860×480检查首页、快速连接、八类设置展开与滚动、Local/AI及重命名取消。加位置参数 `path` 单独复验长中英文下载目录：省略label、完整有界Tooltip和Esc。行为断言、几何候选与像素验收分别记录；runner不调用外部服务或真实删除操作。

传输浅卡片与关闭专项使用 `zig build transfer-controls-preview -Dtest-mode=true -Dtransfer-preview-presentation=global_popover`（另可选`session_popover`、`session_tray`），然后 `node e2e/transfer_controls_native.ts /absolute/bin/transfer-controls-preview /tmp/transfer-controls-new-run fixture`；tray模式用末参数`tray`，正式应用关闭检查用正式test-mode二进制及末参数`main`。该fixture复用生产renderer和按钮，仅使用合成任务。必须检查76px卡片（84px排列节距、3px进度）主行及元信息完整可见、默认不显示复选框、管理后选择、按钮直接展开、450ms hover分组详情及完成上传复制路径、SFTP按owner及上传/下载方向分列、无任务隐藏且不占位、卡片之间无细线分割、X后面板隐藏及重新打开后的第二次关闭，不能只验发送click成功。

传输入口、轮播和未读角标专项：先执行 `zig build -Dtest-mode=true -j2`，再运行 `ZW_TEST_PYTHON=/absolute/python-with-paramiko node e2e/transfer_entrypoints_native.ts /absolute/bin/zerowork /absolute/fresh-output --live-transfers`。同一命令增加 `--foreground` 验证前台底栏直接展示后清除角标，会激活独立临时数据窗口；默认后台模式验证未查看角标 2 → 打开列表清零 → 新任务角标 1 → 再次查看清零。两种模式均使用自建 loopback SFTP、实际上传和接收端 SHA-256，核对 3 秒轮播、进度／速度／数量、悬停不弹窗、两个入口共用右上角浮窗、860×480、任务完成后不恢复角标和正常 Quit。Runner 设置 `ZENIT_E2E_REAL_ACTIVATION=1`，避免 Harness 默认的活动外观模拟掩盖真实前后台状态。SFTP 栈溢出定向回归为 `zig build test-ui -Dui-test-filter='SFTP progress' -j2`，包括 2 MB 栈上的连续刷新与快照独立性检查。

通用结构回归：`zig build test-ui -Dui-test-filter='UI constraints' -j2`。其他模块专项及未通过边界见，不能将单个runner通过称为所有操作全绿。

## 启动守卫：只启动 test-mode 构建

正式构建（不带 `-Dtest-mode=true`）按设计只读真实家目录，HOME / CFFIXED_USER_HOME 覆盖对它无效，用它跑 e2e 会写进 `~/Library`。所以 e2e 启动任何 ZeroWork 产物（主程序、预览 / 夹具 / runner、更新器、改名副本或包着它们的 `.app`）之前，都先按字节查 `ZEROWORK_BUILD_MODE=test-mode` 标记（`src/platform/build_mode_marker.zig`；只在 test-mode 构建里导出，`check-test-hooks` 在安装时双向核对），不执行被检查的二进制去“问”——正式构建会忽略探针参数、直接以真实家目录启动。

- `e2e/regression/build_mode_guard.mjs`：导入即给 `node:child_process` 的 spawn / spawnSync / execFile / execFileSync（含 promisify）/ exec / execSync 装钩子；`open <bundle>` 也查包内可执行文件。凡是导入 `node:child_process` 的 e2e 脚本都先导入它，`run.ts`、`isolation_guard.mjs` 同样导入；`run.ts` 另外在开跑前核对 `--binary` 和前缀里所有 ZeroWork 产物。没有绕过开关。
- `e2e/regression/build_mode_guard.py`：Python 版。`ai_session_controls_native.py`、`app_update_native.py`、`app_update_runtime_native.py` 启动前调用 `assert_test_mode_binary`；凡是接收 `--runner` / `--binary` 的 Python 脚本（acceptance runner 或 `zig build` 导出的 Zig 测试二进制，如 `ssh-shell-product-tests`、按 `-Dtest-filter` 编出的 `unit-tests`）在解析参数后立即调用 `assert_runner_binary`：runner 必须带 test-mode 标记；Zig 测试二进制按 std 测试运行器的字节（`internal test runner failure`，只链进 `zig build test*` 产物，都是 `builtin.is_test` 的隔离构建）放行；其余一律拒绝。
- 负向测试 `e2e/regression/build_mode_guard_selftest.ts`：`zig build -j2 --prefix /private/tmp/zw-<包>-formal` 装一个正式构建（不许装进 zig-out），再 `node e2e/regression/build_mode_guard_selftest.ts --formal /private/tmp/zw-<包>-formal/bin/zerowork --binary <test-mode zerowork> --out <目录> [--zig-test <某个 Zig 测试二进制>]`。它不启动任何应用，并核对每个导入 `node:child_process` 的脚本都导入了守卫、每个接收 `--runner` / `--binary` 的 Python 脚本都调用了 `build_mode_guard.py`。
- **包级门禁必跑**：运行器只拿得到 test-mode 前缀，所以清单把 `regression__build_mode_guard_selftest` 标成 `excluded`（formal-binary），批量回归不会跑它。每个包 / 每批收尾的门禁脚本都要单独跑上一条负向测试（正式构建只装进 `/private/tmp/zw-<包>-formal`，跑完删掉），与 check-yix、check-arch、build、compile-tests、test / test-ui、窗口渲染冒烟一起记进门禁结果；它失败时本批不算通过。
- 门禁脚本里 test-mode 构建失败必须立即中止，不许接着用旧产物跑 e2e；守卫是最后一道防线，不替代这一条。

## 家目录隔离（test-mode 构建、预览与夹具）

`-Dtest-mode=true` 的 App、更新器 helper / update-fixture、所有 `src/preview.zig` 预览与夹具和验收 runner 只从 `platform/user_dirs.zig` 取家目录：用进程的 `HOME`，它必须是已存在、不是真实账户家目录、不是其祖先、也不在其之下的目录；设置了 `CFFIXED_USER_HOME` 时必须与 HOME 指向同一目录。不满足就在 `main` 第一行拒绝启动（stderr 打印 `ZeroWork test build refuses to start (...)`），不回退到真实 `~`。预览与夹具同样认 `ZEROWORK_DATA_DIR`；测试构建不写 `~/Library/Preferences/<bundle id>.plist`（Dock 图标只更新运行中的图标）。设计与理由见 [docs/ui-revamp/HOME_ISOLATION.md](../docs/ui-revamp/HOME_ISOLATION.md)。

回归运行器（`e2e/regression/`，见 e2e-migrate 包）据此可以把因“写真实家目录”排除的条目有条件放回：条件是该构建包含本修复（`user_dirs.zig` 存在且 `zig build test -Dtest-filter='home isolation guard'` 通过）、条目在运行器的私有 HOME 下运行（`HOME` = `CFFIXED_USER_HOME` = 私有根，`ZEROWORK_DATA_DIR` 私有），并且第一次放回时用 `--jobs 1` 单独跑、保留真实家目录前后比对。`home_guard.PRODUCT_POLICY` 中对 `transfer-controls-preview`、`forward-config-preview` 的 `refuse` 可改为 `data`。临时 `.app`（`local.zerowork.*` bundle id）一类条目的应用自有偏好写入已关闭，但 AppKit / CFNetwork 按 bundle id 写入的系统文件（如 Saved Application State、URL 缓存）不经本应用路径，放回前仍需以前后比对实测确认。e2e-migrate 包的落实：两个预览的策略已改为 `data`；`transfer_controls_native` 首次 `--jobs 1` 单独跑、真实家目录前后无变化，但脚本断言仍是 Island B v3 之前的 76 px 卡片（现为 54 px 浮窗行），改按 `stale-assertion` 排除；`copy_feedback_native` 改按“写用户真实剪贴板”排除；临时 `.app` 一类本批仍排除。

单独跑测试或脚本时同样要给私有 HOME（Zig 的全局缓存随 HOME 移动，用 `ZIG_GLOBAL_CACHE_DIR` 指回原处）：

```sh
R=/private/tmp/zw-<任务>; mkdir -m 700 -p $R/home $R/tmp $R/data
HOME=$R/home CFFIXED_USER_HOME=$R/home TMPDIR=$R/tmp/ ZEROWORK_DATA_DIR=$R/data ZIG_GLOBAL_CACHE_DIR=<原全局缓存> \
  zw-nonet.sh zig build test -Dtest-filter='home isolation guard'
```

## 私有实机输入与证据

仓库不保留实际服务器配置、主机指纹、Provider 私有端点或密钥；一次性用户网络验收脚本已清理。保留的 loopback/fixture 及本地回归只使用受控资源。远端 CLI 验证必须显式提供主机；VM 专项使用 `ZEROWORK_VM_HOST` 与密码，涉及固定信任校验时还需调用者提供 `ZEROWORK_SFTP_FINGERPRINT`，不得放宽指纹检查。

AI gateway 专项默认跳过；明确开启后必须同时提供 `ZEROWORK_AI_GATEWAY_KEY`、`ZEROWORK_AI_GATEWAY_MODEL`、`ZEROWORK_AI_GATEWAY_CHAT_ENDPOINT` 与 `ZEROWORK_AI_GATEWAY_MODELS_ENDPOINT`。这些只供独立测试进程使用，不是正式 App 配置入口。`v02_grok_gateway.py` 从仓库外 mode-600 配置加载单个 Grok 模型，不使用隐式网关或模型回退。

截图、节点树、运行日志和私有配置保存在仓库外的临时目录，验收后清理，不提交。当前 V3 原型结论与 App 尚未完整同步的边界见。

## 保留的旧认证组件与端口转发回归

旧 `auth_challenge_view` 当前没有生产调用入口。使用 `zig build auth-challenge-preview -Dtest-mode=true` 构建隔离原生验收窗口，再运行 `node e2e/legacy_auth_native.ts /tmp/legacy-auth-new-run dark`（另测 `light`）。窗口复用真实 View 和 InteractiveBridge，覆盖五种认证、标准／最小尺寸、输入遮罩、提交／取消、首次密钥三个决定，以及变更密钥无需输入确认词、点击一次确认即可替换；不建立 SSH、不写信任记录或钥匙串。图标与三主题重着色由 `zig build test-ui -Dui-test-filter='auth challenge'` 验证。

生产转发完整回归使用 `node e2e/forward_controls_native.ts /tmp/forward-new-run dark`（另测 `light`）。只点击一次主机入口；同一 SSH transport 应包含一个 PTY channel 和一个只读系统识别 channel。对端仅将与生产 `remote_os.command` 完全相同的探测记为 `os_probe` 并拒绝执行，其他 exec 仍导致验收失败。三种转发均需完成 8192 字节精确往返、停止后拒绝连接；收尾保留原始 peer trace，再检查唯一 transport、通道数和流量，不能靠删除失败断言通过。


历史PATCH局部回归：`node e2e/patch_history_native.ts zig-out/bin/zerowork /tmp/zerowork-history-review`。先构建最新test-mode二进制；runner只在独立临时数据目录写种子cast/索引，通过主机菜单打开归档，核对Esc、搜索后Esc、1440×900及860×480卡片与内容，保存真实Metal截图。它不连接SSH，也不代表真实远端resize、正常Quit或完整新PATCH已验收。

## 2026-11-04 AI 会话效率验证

契约和实际结果见 [AI_SESSION_EFFICIENCY.md](../docs/DESIGN/AI_SESSION_EFFICIENCY.md)。定向核心回归：`zig build test -Dtest-filter=efficiency -j2`、`zig build test -Dtest-filter='image offload' -j2`、`zig build test-bmc -j2`。Local 原生验收 `ai_execution_lifecycle_native.ts` 使用 interactive readiness、同调用短等待及 terminal wait；分别核对模型精简结果、test-mode 原始 host_result 与落盘 journal/recording，避免用模型文本替代原生执行证据。SSH 使用 `ssh_shell_execution_loopback.py` 的 nominal/nested 模式；KVM 渲染使用 `bmc_kvm_video_frames_native.ts`。实机连接与真实模型渠道另行记录，不以这些隔离 fixture 冒充。

普通受控输入可用 `ZW_AI_TEST_INPUT_ONLY=1` 运行 `ai_execution_input_native.ts`，同时提供 `ZW_AI_TEST_PREFIX` 和与该构建一致的 `ZW_AI_TEST_EXPECTED_SHA256`。该模式核对真实两段文本、单独 Enter、同 key 不重写、模型 consumed 回执与原始 host/journal 证据，正常退出；不打开独立安全输入收集器，也不宣称完成默认三阶段的全部验收。默认完整模式继续保留三个阶段及真实 CUA 安全输入要求。


会话组控件集成验证：先构建 `zig build -Dtest-mode=true -j2`，再运行 `node e2e/session_group_controls_native.ts --binary /absolute/path/to/zerowork --expected-sha <该二进制的SHA256> --out /absolute/empty/evidence`。Runner 使用独立配置、三个真实 Local PTY 和自建回收的 loopback 端口，验证候选滚动、排序／取消、连续拖动建组／入组、独立广播的真实 PID 输入分发、当前成员取消、批量开关、小窗口及选主机新建后保留组。`--pointer-handoff 1` 另建独立原生 App，分别在排序和组右键阶段写入 handoff.json；执行所列 CUA 动作后才写对应 done 标记。未实际执行不能写标记冒充通过。截图人工查看与报告断言分别记录，真实 SSH 重连和 IME 不由此 Runner 证明。


分层与保留面板回归：`zig build -Dtest-mode=true -j2 --prefix /tmp/zw-layer-build` 后运行 `node e2e/layer_regressions_native.ts /tmp/zw-layer-build/bin/zerowork /tmp/zw-layer-regressions`。通过生产设置在 AI 首次打开前、收起后切换三主题，核对原节点、未发送草稿、反复重开及860×480；使用合成背景和独立Local PTY，不发送模型或SSH请求。脚本调用 `layer_regression_pixels.py`（与现有像素回归一样依赖 Pillow），拒绝空白浮层变为整块实色，检查重复重开没有累计加实，以及深色主题草稿确实绘制浅色文字。对应生产组件alpha和内部菜单归属断言：`zig build test-ui -Dui-test-filter=material -j2`。截图仍需人工查看。


开机命令回显回归：先运行 `zig build ssh-shell-execution-acceptance -j2 -Doptimize=ReleaseFast`，再用已安装 Paramiko 的 Python 执行 `e2e/ssh_startup_commands.py --runner zig-out/bin/ssh-shell-execution-runner --output /tmp/zerowork-startup-check`。测试使用隔离的本地 SSH 和真实 Bash/Zsh PTY，检查延迟提示符下逐条执行与单次回显、提示符超时，以及交互式命令后的人工输入恢复；不连接已保存主机。

v0.4 首个基础增量（Worker 回收）：先执行 `zig build -Dtest-mode=true -j2 --prefix /tmp/zw-v04-build`，再运行 `ZW_AI_TEST_PREFIX=/tmp/zw-v04-build node e2e/ai_worker_release_native.ts /tmp/zw-v04-worker-native`。Runner 启动隔离的生产 App、真实 Local PTY 和 loopback Provider，核对宿主查询的真实工具结果、结束并解绑后历史／草稿保留、恢复不请求模型、明确再次发送后重建执行、流式响应中取消并解绑、860×480 和应用级正常 Quit。报告记录二进制 SHA-256、请求、journal 及 Metal 截图，截图需实际查看。仅 Provider 输出由 fixture 控制；不连接已保存主机或真实模型，不代表子 Agent／技能／MCP 已验收。对应服务回归为 `./scripts/test_isolated.sh test -Dtest-filter='v0.4 Worker' -j2`，包括清理等待、最终保存失败、释放后解绑提交失败及旧 fence 不影响新 Worker；现有 `AiHost integration` 用例继续覆盖回答恢复与跨窗口归属。

应用更新完整回归：`zig build -Dtest-mode=true -Doptimize=Debug -j2 --prefix /tmp/zw-update-e2e` 后执行 `node e2e/app_update_full_native.ts /tmp/zw-update-e2e /tmp/zw-update-normal`，以及 `node e2e/app_update_full_native.ts /tmp/zw-update-e2e /tmp/zw-update-force force`。仅 HTTP 响应由本地签名包提供；运行真实主程序、下载与签名校验、独立安装程序、替换和自动重启，核对旧进程退出、启动／healthy 回执、新版窗口、版本页、严格代码签名及数据保留。所有应用与数据均隔离，不替换已安装应用。`app_update_deleted_drafts_native.ts` 另外覆盖先报错、关闭、删除全部会话后重新安装的旧错误缓存回归。


v0.4 子记录与恢复基础：`./scripts/test_isolated.sh test -Dtest-filter='v0.4 child' -j2` 覆盖独立身份与主 owner 索引、当前父 fence／精确 generation、独立／继承上下文、创建键冲突与内容哈希、混合 schema 回放、显式家庭删除、分配失败回滚、独立 Worker、Task 范围停止及父级 End、子成员读取投影与空工具目录。构建 test-mode 到 `/tmp/zw-v04-child-build` 后，运行 `ZW_AI_TEST_PREFIX=/tmp/zw-v04-child-build node e2e/ai_child_recovery_native.ts /tmp/zw-v04-child-recovery-native`：隔离日志保存旧父子绑定，真实 App 先回收孩子再回收父级，子记录不进入主列表，显式恢复父对话不调用模型，再次发送沿新 AgentId 使用原 ConversationId；保留原 child identity／创建来源且不自动绑定子 Worker。报告含二进制 SHA-256、原 journal、标准／860×480 Metal 截图和应用级 Quit 结果。该专项不创建模型子任务，不作为任务协作／预算／技能／MCP／子弹窗已完成的证据。


v0.4 子任务协作增量：`./scripts/test_isolated.sh test -Dtest-filter='v0.4' -j2` 覆盖共享请求／工具预算、人工与模型排队时间、全局 4／根 2 模型槽及根间轮转、4 个未收尾孩子、原子首任务提交与分配失败、任务日志 schema 3 和降级拒绝、重启不复活、回执幂等、事件确认无自唤醒、复用 generation、当前 handoff fence、压缩请求统一计费及最终事实提交重试。宿主桥定向回归为 `./scripts/test_isolated.sh test-ui -Dui-test-filter='host' -j2`。

原生协作验收：`zig build -Dtest-mode=true -j2 --prefix /tmp/zw-v04-task-build` 后运行 `ZW_AI_TEST_PREFIX=/tmp/zw-v04-task-build node e2e/ai_task_gateway_native.ts /tmp/zw-v04-task-gateway`；另以新的输出目录追加 `steer` 参数，验证父级等待孩子时用户引导仍进入原 Task／Turn。脚本使用隔离数据、真实 Local PTY 和 loopback Provider，经真实模型工具目录创建仅材料子任务，检查子级不获得委派能力、父级提前回答后保留原 Task 等待并收集真实报告、孩子释放早于父级完成、原根任务收尾后才消费 queue，以及累计请求／工具计数和正常应用 Quit。报告含请求、journal、二进制哈希和原生截图，需实际查看。无远端命令、付费模型或已保存主机操作；不作为子弹窗、人工审批交互入口、异步交接、技能或 MCP 已完成的证据。


本地技能与 MCP 专项：`zig build -Dtest-mode=true --prefix /tmp/zw-v04-extensions-build -j2` 后运行 `ZW_AI_TEST_PREFIX=/tmp/zw-v04-extensions-build node e2e/ai_extensions_native.ts /tmp/zw-v04-extensions-native`。使用隔离数据目录、Local PTY、受控 Provider 和真实本地 stdio / HTTP MCP 服务，验证原生导入／查看、两种配置表单、只发现能力的显式连接测试、秘密引用保存、撤销、紧凑窗口、确认模式审批及技能读取到 MCP 材料调用的真实工具链；不执行终端业务命令，正常应用退出。系统文件选择器、真实拖入和第三方远端认证不在自动化覆盖范围。

v0.4 默认策略与活动子任务交接：构建 `zig build -Dtest-mode=true -j2 --prefix /tmp/zw-v04-completion` 后运行 `ZW_AI_TEST_PREFIX=/tmp/zw-v04-completion node e2e/ai_child_defaults_handoff_native.ts /tmp/zw-v04-child-handoff-native`。使用隔离配置、Local PTY 和 loopback Provider；实际搜索并选择子 Agent 默认上下文／复用策略，验证全局保存、撤销和 860×480 窗口；省略 reusable 使用捕获的 prefer_reuse，显式 independent 覆盖继承默认。让子 Provider 真正运行后由父级调用 create_group，核对子请求取消与解绑先于 handoff，父级保留原 Task／root、收取报告后完成，并正常应用级 Quit。产物包含二进制哈希、请求、journal、设置几何和原生截图。该专项只证明设置与交接；子 Agent 列表、可写弹窗和独立审批另见下述子对话专项。

对应定向检查：`./scripts/test_isolated.sh test -Dtest-filter='v0.4' -j2`，`./scripts/test_isolated.sh test -Dtest-filter='settings' -j2`，`./scripts/test_isolated.sh test-ui -Dui-test-filter='lifecycle controller' -j2` 和 `./scripts/test_isolated.sh test-ui -Dui-test-filter='tab grouping native drop' -j2`。异常复用覆盖当前账本与恢复事实、只读新任务不改写旧 unknown、伪造动态写调用被宿主拦截、目标不相交与 reconnect generation 不能绕过重叠约束；拖放检查等待期间不建半成品组、原目标成员版本变化时不发布。


v0.4 子智能体对话与设置气泡：`zig build -Dtest-mode=true --prefix /tmp/zw-child-ui-build -j2` 后运行 `ZW_AI_TEST_PREFIX=/tmp/zw-child-ui-build node e2e/ai_child_dialog_native.ts /tmp/zw-child-dialog-new-run`。使用隔离数据、真实 Local PTY 与 loopback Provider，验证子提问／审批只消费原子票据、命令仅执行一次、父子草稿和真实拖入图片隔离、非复用子对话的显式用户续行、子模型独立与父权限上限、后台 queue／steer、主标题栏打开列表及标题／LOGO／状态列对齐、主子共用 600×456 默认尺寸、设置气泡宽 320 且自然撑高、名称同行与任务记录折叠／展开／数量不截断、时间线几何不变、最大化恢复、收起重开保留草稿、860×480、历史子详情只读与显式恢复父对话不发模型请求，最后正常 Quit。报告记录二进制 SHA-256、请求、journal 和 Metal 截图，必须实际查看。核心与 UI 定向使用 `v0.4`、`AI composer`、`v0.4 child list`、`conversation UI` 过滤器。受控回答不替代真实模型／外部 MCP／远端业务验收。

标准 MCP 与飞书 CLI 只读验收：先构建启用 harness 的应用，运行
`ZW_AI_TEST_PREFIX=/tmp/zw-standard-mcp-build node e2e/ai_extensions_native.ts /tmp/zw-standard-mcp-native`。
真实飞书验证使用 `e2e/lark_cli_mcp_native.ts`，要求现有 `lark-cli` 用户登录，
`ZW_LARK_TEST_DOC_FILE` 指向保存现有已授权文档 URL 的本地文件。
适配器只开放身份、文档目录及搜索读取，复用 CLI 凭据、不导出 token，
只在隔离数据目录配置 MCP。若账号缺少搜索权限，验收确认错误被正确返回，
不会发起额外授权。报告只记录状态与调用名，不保存文档正文或凭据。


## 官方 MCP 参考服务

先构建 `zig build -Dtest-mode=true --prefix /tmp/zw-standard-mcp-build -j2`，再安装固定的官方服务依赖并运行：

```sh
npm ci --prefix e2e/fixtures/mcp-reference --ignore-scripts
ZW_MCP_REFERENCE="$PWD/e2e/fixtures/mcp-reference" node e2e/mcp_reference_native.ts /tmp/zerowork-mcp-reference-evidence
```

Runner 使用未修改的官方 Everything 2.2.1 和 SDK 1.32.2 两个 HTTP 示例，独立启动 Node 服务、原生应用、data/RPC 目录与本地 Provider 响应服务；不接触正式应用配置或飞书数据。验证 stdio／Streamable HTTP、resources／templates／prompts／completion、roots、采样前后人工审阅、表单默认值和拒绝、多轮 opaque requestState、2026 URL 输入、Mcp-Param 请求头及独立 POST SSE 订阅更新、OAuth 401 提示／浏览器 PKCE 登录／受保护工具、URL 导航审阅及 -32042 不自动重放。浏览器会打开 localhost 授权及演示页面；URL accept 表示同意访问，不代表网页事务完成。示例页面不需要真实密钥或付款。

输出包含报告、原生截图和日志。报告记录实际服务版本与执行步骤，最后必须正常退出原生应用并结束自建服务。生产应用不依赖这些 Node 包。`ZW_MCP_START_PHASE=1` 或 `2` 仅用于定向调试后半段；完整验收不设置此变量。

Everything 的 stdio／HTTP 必须实际协商为 2026-07-28；旧版 SDK 示例继续覆盖 2025-11-25 兼容。`ZW_MCP_UI_ONLY=1 ZW_MCP_THEME=reference-light` 可只运行 V4 服务列表的浅色／860×480 几何与原生操作验收，完整运行同时覆盖深色界面。

## 设置窗口（两级导航）e2e

设置窗口自 `936166e1` 起是独立的偏好设置窗口：左侧分类 → 分类概览（每个子页面一行，带实时摘要）→ 子页面（只显示该子页面的 pane），顶部 Back / Forward，左上搜索，右下浮动 Save Bar；pane 不再折叠，也没有 `settings.close` 按钮（Cmd+W 关闭）。`快捷键`、`协议插件`、`关于与更新` 没有概览，直接显示 pane。

- 共享辅助 `e2e/settings_nav.ts`：分类／子页面映射（与 `src/features/settings/view/settings_subpages.zig` 保持一致）、`toCategory`／`toSub`／`toPane`／`toField`（按设置键找到所在子页面）、`back`／`forward`、`reveal`、`close`（Cmd+W 并等待主窗口重新可查询）、`edit`，以及 `launchIsolated`（`mkdtemp` 隔离数据目录、`[updates] auto_check=false`、后台与隔离指针模式）和 `clickLabel`（点击无独立 test_id 的 Tabs 项，如光标形状）。新脚本请复用它，不要再假设“一长页 + 折叠分组”。
- 权威基线：`settings_revamp_native.ts`（截图基线依赖其输出，勿改）。
- 已迁到两级导航并通过的脚本：`settings_v3_native.ts`、`settings_other_v3_native.ts`、`settings_hierarchy_native.ts`、`settings_search_v3_native.ts`（`dark`／`light`）、`settings_save_feedback_native.ts`（`light`／`dark`）、`settings_confirmation_controls_native.ts`（参数为构建 prefix）、`settings_visual_capture.ts`、`settings_summaries_native.ts`、`settings_default_folds_native.ts`（改为“pane 默认展开且重挂载／重开后仍展开”）、`model_settings_controls_native.ts`、`provider_v3_native.ts`、`plugin_settings_v3_native.ts`、`v02_plugins_ui.ts`、`terminal_types_settings_native.ts`、`keybinding_v3_native.ts`（F-set-panes-B 改写为行内录制，见下）。
- `keybinding_v3_native.ts BINARY OUT`：快捷键行内录制（人工验收反馈第 7 条）。暗、亮各一轮：点击键帽区原地录制；⌃⌘X 给出 Control 保留原因；⌘C 冲突提示“复制”并提供【交换】【取消】，取消不改草稿；录制中 ⌘W 被当作组合（与“关闭页签”冲突）、Escape 取消录制，二者都不关窗口；Tab 结束录制；固定行不录制；录到 ⌘⇧X 只改草稿（配置文件不变），Save 后写入 `new_tab = "cmd+shift+x"`；单行恢复默认与交换（new_tab ⌘C ↔ copy ⌘T）保存后持久化，重开窗口仍显示。旧的录制对话框几何、“解除绑定不可用”检查随对话框一起删除。
- `h_keys_capture.ts BINARY OUT`：一次性的验收截图采集（快捷键页 静止／悬停／录制中／冲突／无效／已修改／恢复默认可用，及关于与更新页；明、暗），供第二轮人工验收，不做回归断言。
- 全局通知 toast 发布在主窗口；偏好设置窗口打开时 Harness 绑定的是设置窗口，因此 `settings_save_feedback_native.ts` 改为断言窗口内的字段内联错误与 Save Bar 状态。
- `switch_initial_state_native.ts BINARY OUT [light|dark] [--material]`：开关回归。SSH › 断线重连的 `settings.field.auto_reconnect`（默认开）从页面首帧起逐次查询滑块相对轨道的偏移（布局位置 + translate），≥ 400 ms 内必须一直停在开的静止位置 20；指针移到开关上再点击时只允许 translate 单调滑动（布局位置不变、至少两个中间值）并停在 2，再切回 20；返回后重进同样首帧静止；SSH › 连接的 `settings.field.compression`（默认关）首帧停在 2。`--material` 用合成棋盘壁纸、材质透明度 50 启动。窗口空闲 ≥ 1 s 且无指针移动时直接点击也必须有滑动过渡（zenit G22，上游已修复），结果同时写入 `report.json` 的 `idleClickAnimates`。隔离数据目录、后台窗口。 另对外观与主题 › 终端与工作区里的原生 sm 开关做首帧断言；该页切换开关会整页重建（例外表 S-11），所以目前只断言切换后新节点停在终点、不要求同一节点滑动，3e 外观面板改为局部更新后再收紧。
- `h_tokens_capture.ts BINARY OUT [light|dark|sauber]`：原生组件默认外观对照采集（修复包 H-tokens），只截图不改配置（退出前放弃改动）。依次截取 SSH › 断线重连（自动重连开 / 关，关后依赖开关为禁用态）、外观与主题 › 主题（应用图标单选、材质开关）、外观与主题 › 终端与工作区（开关）、未保存时 Cmd+W 弹出的确认对话框（原生 Modal 遮罩），文件名 `<theme>-<screen>.png`。修复前 / 修复后分别用对应构建各跑一遍即可逐张对照。
- 关闭最后一个主窗口现在保留应用（见 `window_hide_native.ts`），需要正常退出时用 `POST /zerowork/windows {action:'quit'}`。

## 全量回归（`e2e/regression/`）

`e2e/regression/manifest.json` 给 `e2e/` 下每个文件分类：`runnable`（可在隔离环境跑的真实窗口 / 组件脚本，含调用参数、环境变量、light / dark 等变体、需要的预览程序、是否前台）、`helper`（库 / 夹具，不单独运行）、`excluded`（`.py`、依赖未审计的 `.py` 或 `scripts/`、写系统剪贴板、真实网络 / 私有凭据 / 物理输入等，附原因；`stale-assertion` = 目标产物在但断言是旧版式、待重写，`unverified-script` = 原排除理由已失效但脚本尚未按当前界面核对；`.py` 条目另有 `audit` 说明是否需要审计后再跑）、`obsolete`（功能已取消，附依据）。占位符：`{bin}`（`--binary`）、`{prefix}`（`{bin}` 的上两级）、`{out}`（该条目的输出目录）、`{sha}`、`{repo}`、`{fixtures}`（`e2e/regression/fixtures`）、`{variant}`。

```sh
N="${ZW_NONET_WRAPPER:?Set ZW_NONET_WRAPPER to the absolute path of zw-nonet.sh}"
P=/private/tmp/zw-<包名>              # Debug 构建
"$N" zig build install settings-preview file-workspace-preview auth-challenge-preview connection-progress-preview \
  transfer-events-preview transfer-conflict-preview transfer-controls-preview test-notification-preview \
  bmc-kvm-preview forward-config-preview -Dtest-mode=true -j2 --prefix $P
"$N" zig build mockup -Dmockup=yix_spike -Dtest-mode=true -j2 --prefix $P   # yix_spike_native 用的 mockup-yix_spike
"$N" node e2e/regression/run.ts --binary $P/bin/zerowork --out /abs/evidence/regression --jobs 3
# 只复跑失败项（串行，排除并行干扰）
"$N" node e2e/regression/run.ts --binary $P/bin/zerowork --out /abs/evidence/rerun --from-failed /abs/evidence/regression/SUMMARY.tsv --jobs 1
```

标签：`batch5` = 当前失败、归批次 5 修；`e2e-debt` = usage-e2e-debt 判定为脚本过期（断言是旧版式 / 引用已删除的 test_id）、当前失败、尚未重写，条目的 `note` 写了实测的第一个失败点。全量门禁可用 `--skip-tag e2e-debt` 排除它们，修好一条摘一条。

其它选项：`--only a,b`（名字或 `名字:变体`）、`--list`（打印每条的完整命令行，不运行）、`--timeout-scale K`、`--class obsolete`。执行前若筛选结果为空、并发数或超时无效，直接报错。选中需要 Python 的回环用例时，必须通过 `--python /absolute/python` 或 `ZW_TEST_PYTHON` 提供隔离模式下可导入 Paramiko 的解释器；缺少夹具时整轮失败，不静默跳过。运行器入口负向验证：`node --test e2e/regression/runner_gate_selftest.ts`。

- 输出：`SUMMARY.tsv`（脚本、变体、退出码、report status、耗时、泄漏、日志、PASS/FAIL）、`logs/<条目>.log`、`<条目>/`（脚本自己的输出与截图，可直接给 `lead-tools/shotdiff.py` 与基线目录比对）。通过 = 退出码 0 且脚本报告 status 为 `passed`（采集脚本为 `captured`；`passed_pending_<x>_review` 视为自动检查通过、截图待人工看）。
- 每条目：独立进程组、独立 `TMPDIR`（`/private/tmp/zwr-<pid>/<n>`，无符号链接——应用拒绝经 `/var → /private/var` 符号链接到达的数据目录；通过后删除，失败保留）、超时（默认 300 s，可在清单里按条目设 `timeout`）。预加载 `exit_guard.mjs`（脚本正常结束、断言失败、被超时终止时 SIGTERM 它 spawn 的子进程）与 `isolation_guard.mjs`（脚本写出的 `config.toml` 没有 `[updates]` 时追加 `auto_check=false`）。结束后再清扫：该进程组里剩下的进程，以及本条目期间新出现、父进程为 1、可执行文件是 `{prefix}/bin/*` 或其字节相同副本的进程，一律普通 SIGTERM（不用 SIGKILL），写入 `leaks` 列。
- `zig-out`：许多脚本 import `../zig-out/share/zenit/harness/client.ts` 或回退到 `zig-out/bin/*`。运行器要求 `zig-out` 不存在（运行期间临时链接到 `{prefix}`，结束删除）、是符号链接（临时改指 `{prefix}`，结束恢复），或本身就是这次的 test-mode 构建；否则拒绝运行，避免脚本回退到一个正式构建而写用户真实数据。`zig-out/` 的 gitignore 不匹配符号链接，提交时不要 `git add -A`。
- 并行：`--jobs 3` 与串行在设置类脚本上结果一致（后台窗口 + 隔离指针，各自 RPC / 数据目录）；清单里 `foreground: true` 的条目（前台 / 真实激活）总在并行池之后逐条单独跑。整轮失败项建议再用 `--from-failed … --jobs 1` 复跑一次区分并行干扰。
- 沙箱：`/bin/ps` 是 setuid 程序，`zw-nonet.sh` 下不可执行；脚本改用 `e2e/ps_compat.ts`（先调真实 ps，EPERM 时用系统自带 python3 的 ctypes 读 libproc，只读本用户进程，无新依赖、无编译产物）。
- models.dev（robustness 包已解决，原 `releasesafe` 标签已去掉，AI 组与其它条目一起用 Debug 构建跑）：模型列表缺能力元数据时，正式构建回退去拉 `https://models.dev/api.json`；`-Dtest-mode=true` 构建与单元测试不再访问它（`src/ai/model_discovery.zig` 的 `testPublicCatalog`：没有本地夹具就跳过，日志记 `public catalog skipped in test-mode`）。AI 夹具的模型 id 本来就不在 models.dev 上，所以跳过与原先“查不到”的结果一致；需要公共目录元数据的用例把 models.dev 格式的本地文件路径放进 `ZEROWORK_TEST_PUBLIC_MODEL_CATALOG`，或者像 `ai_launcher_native.ts` 那样在 `GET /models` 里给出完整元数据（`context_length` / `reasoning` / `vision`）。另外，所有 std.http 拨号都经 `src/platform/net_connect.zig`：沙箱 / 防火墙让 connect 返回 EPERM 时按普通 `AccessDenied` 处理，界面提示“无法连接 · 系统或防火墙拒绝了网络访问”，不再走 Zig std 的 `errnoBug`（Debug 构建 panic）。
- 不等人：清单里需要真人操作的脚本（真实 NSOpenPanel、CUA 物理点击 handoff、启动恢复提示、授权弹窗 / Touch ID 等）都是 `class: manual`（`reason` 写明需要什么人工操作），不进批量回归；`--class manual --list` 列出它们供有人值守时单独跑。批量运行时运行器去掉环境里所有 `*HANDOFF*` 开关（如 `ZW_SKILLS_PICKER_HANDOFF`），并给每条目一个空的 `ZEROWORK_E2E_DIALOG_DIR`：test-mode 应用弹任何系统文件对话框都按“取消”应答，不会卡在真实面板上；每条目还有超时（默认 300 s）兜底。系统文件对话框在 test-mode 构建里可以注入：设置 `ZEROWORK_E2E_DIALOG_DIR=<dir>`，应用按 `<dir>/queue` 逐行应答（绝对路径 = 选中，`cancel` = 取消，队列用完一律取消，不回退真实对话框），每次请求追加到 `<dir>/requests.jsonl`（实现：`src/platform/dialog_port.zig`、`src/platform/test_dialog_injection.zig`，只在 `-Dtest-mode=true` 编译）。AI 本地附件的批量用例是 `ai_attachments_fixture_native.ts`（脚本临时生成夹具目录，表驱动逐类断言）；真实对话框版 `ai_local_picker_native.ts` 只作手动验收。
- 证据目录只留日志、截图与报告：运行器在每条结束后删除输出目录里与 `{prefix}/bin/*` 字节相同的二进制副本（脚本常把 `zerowork-frozen`、`zw_ipc.so`、临时 .app 冻结进输出目录）。
- 私有 HOME：每条目在 `/private/tmp/zw-e2e-home-XXXXXX`（0700）里准备假 HOME（Library/Application Support、Preferences、Caches，Downloads、Documents，只设 PS1/PATH 的 shell rc）、TMPDIR、XDG_*，并导出 HOME、CFFIXED_USER_HOME、ZDOTDIR、默认 `ZEROWORK_DATA_DIR`（`<根>/data`，0700）、`ZIG_GLOBAL_CACHE_DIR`（指回真实的 `~/.cache/zig`），清空 SSH_AUTH_SOCK；`/tmp`、`/private/tmp` 下的 mkdtemp 被重定向进去；启动应用前断言 HOME / CFFIXED_USER_HOME / TMPDIR / ZEROWORK_DATA_DIR 都在 `/private/tmp/zw-e2e-*` 下（`e2e/regression/home_guard.mjs`、`isolation_guard.mjs`，负向测试 `regression/guard_selftest.ts`）；条目前后比对真实家目录里 `*zerowork*` 的 Library 条目与 Downloads / Documents / Desktop，有改动即判失败；条目结束删除私有根。单独跑脚本也要带上：`node --import ./e2e/regression/exit_guard.mjs --import ./e2e/regression/isolation_guard.mjs e2e/<脚本>.ts …`。脚本里需要家目录时用 `isolatedHome()`，不要用 `process.env.HOME` 或 `os.homedir()`。home-isolation 合入后，测试构建的本地终端初始目录、默认下载目录、数据目录默认值都取自私有 HOME（见 `docs/ui-revamp/HOME_ISOLATION.md`），原先的 getpwuid 限制已不存在。
- 私有剪贴板：每条目设一个独立的 `ZENIT_E2E_PASTEBOARD`（`zw-e2e.<运行器 pid>.<条目>`）。zenit 的剪贴板（`vendor/zenit/native/macos/clipboard_pasteboard.h`，ZeroWork 的复制粘贴都经它）见到它就改用这个私有命名 pasteboard，应用的复制 / 粘贴不再碰用户的系统剪贴板，并行条目也互不可见。脚本读写剪贴板一律用 `e2e/private_pasteboard.ts`（`readPasteboardText` / `writePasteboardText`），不用 `pbpaste` / `pbcopy`；脚本自己 spawn 应用时要么继承 `process.env`，要么显式传 `ZENIT_E2E_PASTEBOARD: pasteboardName()`。条目前后读系统剪贴板的 changeCount（只读），变化即判失败（status `CLIPBOARD-TOUCHED`；运行期间用户自己复制也会触发，重跑即可）；条目结束释放该私有 pasteboard。单独跑会复制的脚本时自己给一个名字：`ZENIT_E2E_PASTEBOARD=zw-e2e.manual.$$ node …`（不设时 helper 拒绝工作，不会退回系统剪贴板）。
- 崩溃报告：测试程序崩溃时，macOS 的 ReportCrash（系统守护进程，不是应用）会写真实家目录的 `~/Library/Logs/DiagnosticReports/<进程>-<时间>.ips` 与 `~/Library/Application Support/CrashReporter/<进程>_<UUID>.plist`。运行器单独对待这两个目录（`home_guard.mjs` 的 `classifyCrashChanges`）：进程名是我们自己的测试二进制（`OWN_CRASH_PROCESS`：`unit-tests`、`ui-tests`、`zerowork`、`*-preview`）且落在本轮时间窗口内的，允许——记入条目日志，整轮结束等 5 秒后汇总到 `CRASH_REPORTS.tsv`，并删除本轮新增的 `.ips` / plist（运行前就存在、只被系统改写的进程 plist 保留并记为 `kept`）；其余与 ZeroWork 相关的变化（时间窗口外、未登记的进程名，含 `{prefix}/bin` 里其他产物名）照旧算碰了真实家目录、整轮停止；别的应用的崩溃报告不管。手动跑 `zig build test` 等不经运行器的命令时，按同一规则事后核对、清理。负向测试见 `guard_selftest.ts`。
- 硬性检查：`--binary` 必须是 `-Dtest-mode=true` 构建；脚本启动的每个构建产物按内容（SHA-256）识别，按 `home_guard.PRODUCT_POLICY` 放行——`zerowork` 必须带私有 `ZEROWORK_DATA_DIR`，不落盘的预览 / 夹具（settings-preview-runner、file-workspace-preview、auth-challenge-preview、connection-progress-preview、transfer-events-preview、transfer-conflict-preview、notification-preview、bmc-kvm-preview）放行；`transfer-controls-preview`、`forward-config-preview` 在 home-isolation 之后是隔离构建（认 `ZEROWORK_DATA_DIR`，无私有 HOME 拒绝启动），策略由 `refuse` 改为 `data`，必须带私有 `ZEROWORK_DATA_DIR`；未登记的产物拒绝启动。任一条目前后发现真实家目录变化，整轮立即停止，SUMMARY 末行写 `!!! ABORTED REAL HOME TOUCHED`。

### 预览产物审计（`home_guard.PRODUCT_POLICY`）

名单里每个产物都要有源码级依据，不能因为“跑过没出事”就加。usage-e2e-debt 补齐了 9 个组件预览（`close-confirmation-preview`、`ai-recovery-preview`、`execution-result-preview`、`task-finish-preview`、`ai-empty-recent-preview`、`inventory-grant-preview`、`button-policy-preview`、`socks-info-preview`、`composer-interaction-preview`），策略都是 `none`。逐项依据：

| 问题 | 结论 | 依据 |
|---|---|---|
| 是不是隔离构建 | 是 | 9 个都由 `build.zig` 以 `src/preview.zig` 为根、`selectRoot` 选中对应 runner（`src/preview.zig` 的分发表）。该根声明 `zerowork_isolated_home = true`，`main` 第一行调用 `platform/user_dirs.zig` 的 `requireIsolatedStartup()`：没有私有 HOME 直接拒启，家目录与 `ZEROWORK_DATA_DIR` 的解析都走 `user_dirs`（`docs/ui-revamp/HOME_ISOLATION.md`）。`-Dtest-mode=true` 产物带启动守卫标记（`strings` 可见 `test build refuses to start`）。 |
| 是否保留磁盘状态 | 否 | 各 runner 只挂生产视图并喂内存里的合成数据：不调用 `platform/applog.zig`（对照：`transfer-controls-preview`、`forward-config-preview` 调用 `applog.init`，所以是 `data`）、不打开会话存储 / 数据目录 / 任何文件（runner 源码与其直接依赖里没有 `user_dirs`、`Paths`、`std.Io.Dir` 文件读写；`ai/tool_results.zig` 的 `Store`、`ai/inventory_grants.zig` 都是纯内存）。运行期实测：每个产物在全新的私有 HOME / TMPDIR / 数据目录里启动、建好界面树、SIGTERM 退出后，三个目录里没有任何文件，真实家目录快照前后一致。 |
| 是否链接网络 / SSH | 否 | `build.zig` 给这 9 个产物只挂 zenit、`icon_ir`、字体与图标资源，不注入 `generated_ssh_*` / `generated_ghostty_vt`（代码里一旦语义引用就编译不过），不链 libssh2 / Mbed TLS / ghostty（`nm` 中 `libssh2_`、`mbedtls_`、`ghostty_` 符号数为 0；对照 `forward-config-preview` 为 390 / 763）。动态库与已在名单里的 `notification-preview` 相同（AppKit / Metal 等系统框架）；未定义符号里的 `socket` / `bind` / `listen` / `connect` / `getaddrinfo` / `NSURLSession` 来自 zenit 自身（自动化 RPC 等），同样与 `notification-preview` 一致。 |
| 负向 | 拒启 | HOME 未设置报 `IsolatedHomeRequired`、HOME 指向不存在的目录报 `IsolatedHomeInvalid`，退出码 1，不创建窗口；HOME 等于真实账户的分支由单测 `home isolation guard` 覆盖（审计不拿真实家目录启动任何产物）。 |

注意两点：

- `button-policy-preview` 的“复制成功 / 失败回执”按钮只调用 `copy.report()`，不写剪贴板。`execution-result-preview` 的“复制输出 / 复制记录”经 zenit 写剪贴板：在运行器里它写的是该条目的私有 pasteboard（见上文「私有剪贴板」），不覆盖用户内容。
- `composer-interaction-preview` 挂的是生产输入区 `Composer.View`（宿主挂的同一个视图：复合 Textarea、工具行、决策面板、“稍后处理”胶囊）加合成的审批 / 提问请求与内存里的问答 Broker；夹具只做宿主那几步投影（面板快照、面板展开时隐藏输入框、边距）。`ai_composer_interactions_native` 测的是主程序，不是这个夹具。
- `socks-info-preview` 是 usage-e2e-debt 新加的构建目标（runner 早就在仓库里，但从没有构建入口、也没编译过）：SOCKS 信息卡视图 + 合成的监听数据，不初始化 applog。

`fixture_window_native` 在批量回归里跑全部 15 个预览 / 夹具产物。审计的原始记录（链接依赖、符号计数、运行期文件清单）在包的证据目录 `home_guard/`。
