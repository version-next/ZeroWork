# 家目录隔离（测试构建）

本文说明 ZeroWork 怎样确定用户家目录，以及测试构建为什么不会写入真实的 `~`。它补充仓库根目录 `AGENTS.md` 的安装与运行规则，不替代该文件。

## 问题

修复前，应用通过 `getpwuid_r` 读取账户记录中的家目录（`platform/account.zig`），本地进程的 C 层（`darwin_process.c`）也直接这样读取；更新器则使用 `NSHomeDirectory()`。这些路径都不看 `HOME`，所以测试无法把它们重定向到私有目录。预览程序和夹具程序还不认 `ZEROWORK_DATA_DIR`，因为它们的 `runtime_mode.automation` 为 false。结果，在批量回归中，`transfer-controls-preview` 写入了真实的 `~/Library/Logs/com.zerowork.app` 和 `~/Library/Application Support/com.zerowork.app/ai-sessions.jsonl.lock`。另外，打包成临时 `.app` 运行的 e2e 脚本保存 Dock 图标样式时（`CFPreferencesSetAppValue`），会在 `~/Library/Preferences` 留下 `local.zerowork.*.plist`。

## 统一入口

`src/platform/user_dirs.zig` 是唯一可以确定家目录的地方：

| 函数 | 结果 |
|---|---|
| `home()` | 所有应用路径的基准家目录 |
| `appSupport()` / `appSupportIn(home)` | `<home>/Library/Application Support/com.zerowork.app` |
| `caches()` / `cachesIn` | `<home>/Library/Caches/com.zerowork.app` |
| `logs()` / `logsIn` | `<home>/Library/Logs/com.zerowork.app` |
| `preferences()` / `preferencesIn` | `<home>/Library/Preferences` |
| `downloads()` / `downloadsIn` | `<home>/Downloads` |
| `updaterSupportIn` | `<home>/Library/Application Support/com.zerowork.updater` |
| `knownHostsIn`、`legacyDataIn` | `<home>/.ssh/known_hosts`、`<home>/.zerowork` |
| `accountHome()` | 账户的 passwd 记录。只用于正式构建的 `home()`，以及“不得把真实家目录当作删除或测试根目录”这类保护检查 |

`config/paths.zig`（数据、配置、缓存、日志、known_hosts）、本地终端的初始目录（`plugins/local/config.zig`、`local/native.zig` 的 `cwdZ(null)`）、下载目录建议（`transfer_host.zig` + `config/transfer_defaults.zig`）、`sftp_engine.zig` 的本地 `~` 展开、`builtin_completion.zig`、SFTP 提供方，以及 Objective-C 更新器的 `ZWRoot()`，都通过它取得家目录。`darwin_process.c` 不再自己查 passwd。

## 两种构建

**正式构建**（不带 `-Dtest-mode=true` 的 `zerowork`、`ZeroWorkUpdater`）：`home()` 就是 `accountHome()`，代码与修复前的 `account.zig` 逐字相同。隔离分支在编译期就被剪掉，进程环境里的任何变量都改变不了路径。更新器仍然使用 `NSHomeDirectory()`。`ZEROWORK_DATA_DIR` 在编译期返回 null。Dock 图标样式照常写入偏好域。

**隔离构建**由 `runtime_mode.isolated_home` 判定，包括单元测试、`-Dtest-mode=true` 的 App、更新器 helper（测试版根文件 `src/update/helper_test_main.zig`）与 update-fixture、`src/preview.zig` 选中的全部预览和夹具，以及 `src/acceptance.zig` 选中的验收 runner（代表正式 App 的 `application-environment-contract` 除外）。这类构建中：

- `home()` = 进程的 `HOME`。它必须指向一个已存在的目录，经 `realpath` 规范化后，不能是真实账户的家目录，不能是其祖先目录（比如 `/`、`/Users`），也不能位于真实家目录之下（比如仓库的 `.zig-cache`）。如果设置了 `CFFIXED_USER_HOME`，它必须解析到同一个目录。
- `home()` 以及由它派生的 `appSupport()`、`logs()`、`caches()`、`preferences()`、`downloads()` 返回前都会经过 `ensureOutsideAccount()`：只要结果位于真实家目录之下，就报 `IsolatedHomeUnderAccountHome`。
- 显式的 `ZEROWORK_DATA_DIR` 可以是任意实例目录（单元测试夹具常用仓库的 `.zig-cache`），但 `checkDataOverride()` 会拒绝真实账户本身、它的 `Library`、`Downloads`、`Desktop`、`Documents`、`.ssh`、`.zerowork` 及其下的路径（报 `IsolatedDataInAccountHome`）。这是纯字符串检查，不会访问真实家目录。
- 每个本地子进程（PTY 与 exec）都经过 `local/native.zig` 的 `cwdZ()`。在隔离构建中，即使调用方给了明确的目录，`cwdZ()` 也会先校验 HOME，所以 HOME 仍是真实账户时，不会启动会继承它的 zsh 或命令。
- 任一条件不满足都直接报错（`IsolatedHomeRequired` / `IsolatedHomeInvalid` / `IsolatedHomeIsAccountHome` / `IsolatedHomeUnderAccountHome` / `IsolatedDataInAccountHome` / `IsolatedHomeMismatch` / `IsolatedHomeUnverifiable`），不会退回真实家目录。App 和每个预览的 `main` 第一行就调用 `requireIsolatedStartup()`，条件不满足就拒绝启动。测试构建的更新器拿不到私有家目录时报“测试构建缺少私有 HOME”，不会使用 `NSHomeDirectory()`。
- 预览和夹具也认 `ZEROWORK_DATA_DIR`。
- Dock 图标只更新运行中的图标，不写 `~/Library/Preferences/<bundle id>.plist`（`user_dirs.writes_user_preferences == false`）。`cfprefsd` 不认 `HOME`，没有可靠的私有路径可以重定向，所以测试构建直接禁止写入。
- 日志（`Paths.diagnostic_directory`）、AI 会话日志及其锁、缓存都放在 `ZEROWORK_DATA_DIR` 或 `<HOME>/Library/...` 下面。更新器的 `check.json`、`active.json`、下载暂存文件放在 `<HOME>/Library/Application Support/com.zerowork.updater/<hash>/` 下面。数据作用域锁本来就放在 `/private/tmp`（以数据目录的哈希命名），与家目录无关。

### 为什么沿用 HOME，而不新增 `ZEROWORK_TEST_HOME`

1. **子进程看到的是同一个家目录。** 本地终端的 zsh、ssh、git 和 MCP 子进程都读取 `HOME`（`.zsh_history`、`.ssh`、`.gitconfig` 等）。如果另设一个变量，应用内部用私有根目录，子进程却仍把 `HOME` 当作真实的 `~`，会照样写进去。沿用 HOME 时，应用和子进程看到的是同一个目录。
2. **能可靠地识别“没有指定”。** 普通 shell 里的 HOME 总是指向真实的 `~`，所以不能只检查“HOME 是否已设置”。我们拿它与 passwd 记录比较（这个记录无法被环境变量伪造），等于真实账户或其祖先时就拒绝，效果与“缺失即拒绝”相同。
3. **现有 runner 已经这样设置。** `e2e/regression` 已经把 `HOME`、`CFFIXED_USER_HOME`、`TMPDIR`、`ZEROWORK_DATA_DIR` 都指向 `/private/tmp/zw-e2e-*`，不需要再增加一个变量。
4. **CFFIXED_USER_HOME 只做一致性校验。** Foundation 的 `NSHomeDirectory()` 认这个变量，`getpwuid` 不认。要求它与 HOME 一致，可以避免 AppKit 和我们使用两个不同的家目录。

## 开发与运行要求

- 所有 `zig build test` / `test-ui` / `test-*` 都需要私有 HOME。例如：`HOME=/private/tmp/zw-x/home CFFIXED_USER_HOME=/private/tmp/zw-x/home TMPDIR=/private/tmp/zw-x/tmp/ ZEROWORK_DATA_DIR=/private/tmp/zw-x/data ZIG_GLOBAL_CACHE_DIR=$REAL_HOME/.cache/zig zw-nonet.sh zig build test …`。目录权限建议设为 0700。改了 HOME 以后，Zig 会把全局缓存放到新的 HOME 下，所以要用 `ZIG_GLOBAL_CACHE_DIR` 指回原来的位置。在真实 HOME 下运行测试，凡是要用家目录的用例都会失败并报 `IsolatedHomeIsAccountHome`，这是预期的保护行为。
- `-Dtest-mode=true` 的 App 和所有预览、夹具，没有私有 HOME 时都会拒绝启动。单独运行 e2e 脚本时要按 `e2e/README.md` 加载隔离预加载脚本。
- 新增代码需要家目录或 `~/Library/...` 下的路径时，只能通过 `platform/user_dirs.zig` 获取。不要直接调用 `getpwuid`、`std.c.getenv("HOME")`、`NSHomeDirectory`、`NSSearchPathForDirectoriesInDomains`、`FileManager urls(for:)`，也不要自己展开 `~`。唯一的例外是视图层的 `features/workspace/view/workspace.zig`：它只用 `HOME` 把显示的 cwd 缩写成 `~`，不拼接也不写入任何路径，而且 check-arch 不允许视图层 import platform。隔离构建里 HOME 已经通过上面的校验，所以显示结果与 `home()` 一致。

## 单元测试中的写入路径

单元测试本身也曾往真实家目录写过东西。2026-11-13 05:26 和 05:36，一个未包含本修复的工作树在真实 HOME 下运行 `zig build test -Dtest-filter=config`。`execution backend new PTY accepts only this Task …`（`src/features/ai/tools/tests/ai_execution_backend_tests.zig`）启动了真实的 Local PTY，`local/recording.zig` 和 `local/adapter.zig` 的 `publishUnrecordedMetadata` 经 `Paths.forApplication` 把会话记录和 `logs/history` 写进了 `~/Library/Application Support/com.zerowork.app/logs/`。

所有 zig 测试二进制（`test`、`test-ui`、`test-local`、`test-bmc`、`test-update`、`test-plugin-fixture` 以及各独立根）都是 `builtin.is_test`，因此都是隔离构建。凡是需要解析数据、日志或家目录的路径，只有两个合法去处：测试自己通过 `ZEROWORK_DATA_DIR` 或 `Paths.fromDirectory` 给出的临时目录，或测试运行器设置的私有 HOME 与 `ZEROWORK_DATA_DIR`。两者都没有时，这些路径会直接报错，不会回落到真实的 `~`。`scripts/test_isolated.sh` 已经同时设置私有 HOME、`CFFIXED_USER_HOME`、`TMPDIR` 和 `ZEROWORK_DATA_DIR`。

以下测试会启动 PTY 或命令、写会话记录、history 或日志，或解析数据目录与家目录。它们现在都受上述规则约束，不需要逐个修改：

- 真实 Local PTY 或 exec 加记录：`features/ai/tools/tests/ai_execution_backend_tests.zig`、`features/ai/tools/tests/ai_local_tools_tests.zig`、`features/ai/tools/tests/host_terminal_queries_tests.zig`、`features/terminal/tests/terminal_execution_tests.zig`、`features/terminal/tests/terminal_focus_local_tests.zig`、`local/tests/local_adapter_tests.zig`、`local/tests/local_process_tests.zig`、`local/tests/local_trusted_edit_tests.zig`、`src/tests_local.zig`（`test-local`），以及 `features/shell/host/application_host.zig` 中的 owned-zsh 夹具（自行设置 `ZEROWORK_DATA_DIR` 和 `ZDOTDIR`）。
- 工作区或 ApplicationHost 运行时（`session_runtime.zig` 经 `Paths.forApplication` 开启记录）：`features/connections/progress/tests/connection_host_tests.zig`、`features/files/tests/file_workspace_presentation_tests.zig`、`features/files/tests/file_mkdir_view_tests.zig`、`features/connections/auth/tests/totp_autofill_tests.zig`、`host/tests/file_workspace_controller_tests.zig`、`host/tests/session_host_background_tests.zig`、`host/tests/sftp_directory_recovery_tests.zig`、`host/tests/socks_route_host_tests.zig`，以及 `features/ai/tools/host/ai_lifecycle_controller.zig` 的引导测试（缺少 `ZEROWORK_DATA_DIR` 时本来就报错）。
- 直接解析家目录或数据目录：`config/paths.zig`、`plugins/local/config.zig`、`transfer/sftp_engine.zig`（`~/Downloads` 展开）、`platform/applog.zig` 与 `platform/tests/applog_tests.zig`（显式 dir 或 `Paths`）。

用本修复运行 `zig build test -Dtest-filter='execution backend'` 时，会话记录全部落在私有的 `ZEROWORK_DATA_DIR/logs` 下，真实的 `~/Library/Application Support/com.zerowork.app` 前后没有变化。

## 守卫与证据

- `src/platform/tests/home_isolation_tests.zig`（`zig build test -Dtest-filter='home isolation guard'`）：
  1. 用一个 0700 的假私有根目录启动关键路径：数据目录、config、hosts、known_hosts、缓存、默认日志目录、旧数据目录、Application Support、Logs、Caches、Preferences、Downloads、默认下载目录 `~/Downloads`、不指定目录时本地终端的初始目录、更新器 C ABI，以及显式 `ZEROWORK_DATA_DIR`。断言这些路径全部落在私有根目录下面，并断言测试构建不写偏好。
  2. HOME 未设置、为空、是相对路径、不存在、等于真实账户、是账户的祖先、为 `/`，或 `CFFIXED_USER_HOME` 不一致时，`home()`、`Paths.forApplication`、`cwdZ(null)`、`downloads()` 和更新器 ABI 都报错，不退回账户家目录。另外验证：HOME 位于真实家目录之下（仓库 `.zig-cache`）时报 `IsolatedHomeUnderAccountHome`；HOME 是真实账户时，带明确目录的 `cwdZ` 也会拒绝；`ZEROWORK_DATA_DIR` 指向账户本身或其 `Library`、`Downloads`、`.ssh`、`.zerowork` 下的路径时，`Paths.forApplication` 报 `IsolatedDataInAccountHome`；指向私有根目录的符号链接会被接受，并规范化成该根目录。假的私有根目录用 mkdtemp 建在 TMPDIR（或 `/private/tmp`）下，不用 `std.testing.tmpDir`，因为后者位于家目录内的 `.zig-cache`。
  3. `Resolver(false)` 就是正式构建编译的代码。即使 HOME 和 CFFIXED_USER_HOME 都指向私有根目录，它返回的仍是 passwd 家目录，说明正式构建没有覆盖入口。
- `zig build test-app-environment`：在正式默认设置下编译探针，并在运行步骤里把 `HOME`、`CFFIXED_USER_HOME`、`ZEROWORK_DATA_DIR`、`ZEROWORK_TEST_HOME` 都指向别处。探针用自己的一份 passwd 读取代码作为基准，并按修复前的拼接方式逐字核对：数据、config、hosts、known_hosts、缓存、日志、旧数据目录、Downloads、Preferences 和本地终端初始目录都必须与基准相同，`user_dirs.isolated` 必须为 false，偏好写入必须保持开启。
